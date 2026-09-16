#!/bin/bash
#
# failed_login_audit.sh
#
# Scans system authentication logs for failed SSH login attempts and
# generates a summary report: total count, top offending IP addresses,
# top targeted usernames, and recent attempts.
#
# Usage:
#   ./failed_login_audit.sh [-f LOGFILE] [-t TOP_N] [-s SINCE] [-o output.txt]
#
#   -f LOGFILE   Explicit log file to scan (default: auto-detect
#                /var/log/auth.log or /var/log/secure; falls back to
#                'journalctl -u sshd' if neither file exists)
#   -t TOP_N     Number of top IPs/usernames to show (default: 10)
#   -s SINCE     Only consider entries since this time when using journalctl
#                fallback, e.g. "today", "1 hour ago", "2026-09-01"
#                (default: "24 hours ago"). Ignored when reading a log file
#                directly, since plain-text logs are scanned in full.
#   -o FILE      Also write the report to a text file
#   -h           Show this help
#
# Detects two attack patterns from sshd log lines:
#   - "Failed password for [invalid user] USERNAME from IP"
#   - "Invalid user USERNAME from IP"
#
# Exit codes: 0 = success, 1 = error (no log source found)

set -uo pipefail

LOGFILE=""
TOP_N=10
SINCE="24 hours ago"
OUTPUT_FILE=""

usage() {
    grep '^#' "$0" | sed -n '2,22p' | sed 's/^# \{0,1\}//'
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f) LOGFILE="$2"; shift 2 ;;
        -t) TOP_N="$2"; shift 2 ;;
        -s) SINCE="$2"; shift 2 ;;
        -o) OUTPUT_FILE="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown argument: $1" >&2; usage ;;
    esac
done

if ! [[ "$TOP_N" =~ ^[0-9]+$ ]]; then
    echo "Error: -t must be a positive integer." >&2
    exit 1
fi

report() {
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$1" | tee -a "$OUTPUT_FILE"
    else
        echo "$1"
    fi
}

[[ -n "$OUTPUT_FILE" ]] && > "$OUTPUT_FILE"

REPORT_DATE=$(date '+%Y-%m-%d %H:%M:%S %Z')
HOSTNAME_VAL=$(hostname 2>/dev/null || echo "unknown")

# --- Determine log source ---
raw_log=$(mktemp)
source_desc=""

if [[ -n "$LOGFILE" ]]; then
    if [[ ! -f "$LOGFILE" ]]; then
        echo "Error: specified log file not found: $LOGFILE" >&2
        rm -f "$raw_log"
        exit 1
    fi
    cat "$LOGFILE" > "$raw_log" 2>/dev/null || sudo cat "$LOGFILE" > "$raw_log" 2>/dev/null
    source_desc="$LOGFILE"
elif [[ -f /var/log/auth.log ]]; then
    cat /var/log/auth.log > "$raw_log" 2>/dev/null || sudo cat /var/log/auth.log > "$raw_log" 2>/dev/null
    source_desc="/var/log/auth.log"
elif [[ -f /var/log/secure ]]; then
    cat /var/log/secure > "$raw_log" 2>/dev/null || sudo cat /var/log/secure > "$raw_log" 2>/dev/null
    source_desc="/var/log/secure"
elif command -v journalctl >/dev/null 2>&1; then
    journalctl -u sshd --since "$SINCE" --no-pager > "$raw_log" 2>/dev/null
    source_desc="journalctl -u sshd --since \"$SINCE\""
else
    echo "Error: no auth log found (checked /var/log/auth.log, /var/log/secure) and" >&2
    echo "'journalctl' is not available. Use -f to point at a specific log file." >&2
    rm -f "$raw_log"
    exit 1
fi

if [[ ! -s "$raw_log" ]]; then
    echo "Error: could not read log data (permission denied, or log/journal is empty)." >&2
    echo "Try running with sudo." >&2
    rm -f "$raw_log"
    exit 1
fi

report "========================================================"
report " FAILED SSH LOGIN AUDIT REPORT"
report " Host       : $HOSTNAME_VAL"
report " Log source : $source_desc"
report " Generated  : $REPORT_DATE"
report "========================================================"
report ""

# --- Extract failed attempts ---
# Pattern 1: "Failed password for [invalid user] USER from IP port ..."
# Pattern 2: "Invalid user USER from IP"
failed_lines=$(mktemp)
grep -E "Failed password|Invalid user" "$raw_log" > "$failed_lines" 2>/dev/null

total_failed=$(wc -l < "$failed_lines" | xargs)

if [[ "$total_failed" -eq 0 ]]; then
    report "✅ No failed SSH login attempts found in the scanned log data."
    rm -f "$raw_log" "$failed_lines"
    exit 0
fi

report "Total failed login attempts: $total_failed"
report ""

# Extract IP addresses (IPv4) from failed lines
ip_list=$(mktemp)
grep -oE "from ([0-9]{1,3}\.){3}[0-9]{1,3}" "$failed_lines" | awk '{print $2}' > "$ip_list"

# Extract usernames from both patterns
user_list=$(mktemp)
grep -oE "(Failed password for (invalid user )?|Invalid user )[a-zA-Z0-9_.-]+" "$failed_lines" \
    | sed -E 's/Failed password for (invalid user )?//; s/Invalid user //' > "$user_list"

unique_ip_count=$(sort -u "$ip_list" | wc -l | xargs)
unique_user_count=$(sort -u "$user_list" | wc -l | xargs)

report "Unique source IPs   : $unique_ip_count"
report "Unique usernames tried: $unique_user_count"
report ""

report "---- TOP $TOP_N OFFENDING IP ADDRESSES ----"
if [[ -s "$ip_list" ]]; then
    sort "$ip_list" | uniq -c | sort -rn | head -n "$TOP_N" | while read -r count ip; do
        report "  $count attempt(s)  from  $ip"
    done
else
    report "  (no IP addresses could be extracted from log lines)"
fi
report ""

report "---- TOP $TOP_N TARGETED USERNAMES ----"
if [[ -s "$user_list" ]]; then
    sort "$user_list" | uniq -c | sort -rn | head -n "$TOP_N" | while read -r count user; do
        report "  $count attempt(s)  for user  '$user'"
    done
else
    report "  (no usernames could be extracted from log lines)"
fi
report ""

report "---- MOST RECENT 10 FAILED ATTEMPTS ----"
tail -n 10 "$failed_lines" | while IFS= read -r line; do
    report "  $line"
done
report ""

# Flag any IP with a high attempt count as a likely brute-force source
report "---- BRUTE-FORCE INDICATORS (>= 10 attempts from one IP) ----"
brute_found=false
if [[ -s "$ip_list" ]]; then
    while read -r count ip; do
        if [[ "$count" -ge 10 ]]; then
            report "  ⚠ $ip made $count failed attempts — consider blocking (e.g. fail2ban, firewall rule)"
            brute_found=true
        fi
    done < <(sort "$ip_list" | uniq -c | sort -rn)
fi
[[ "$brute_found" == false ]] && report "  None detected."
report ""

report "========================================================"
report " END OF REPORT"
report "========================================================"

[[ -n "$OUTPUT_FILE" ]] && echo "" && echo "Report saved to: $OUTPUT_FILE"

rm -f "$raw_log" "$failed_lines" "$ip_list" "$user_list"
exit 0
