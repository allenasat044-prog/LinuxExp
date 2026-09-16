#!/bin/bash
#
# suspicious_ip_detection.sh
#
# Analyzes SSH authentication logs to identify IP addresses responsible
# for repeated failed login attempts, classifies them by severity, and
# can optionally export a plain IP blocklist file for use with a
# firewall or fail2ban.
#
# Usage:
#   ./suspicious_ip_detection.sh [-f LOGFILE] [-t THRESHOLD] [-s SINCE] [-b blocklist.txt] [-o output.txt]
#
#   -f LOGFILE     Explicit log file to scan (default: auto-detect
#                  /var/log/auth.log or /var/log/secure; falls back to
#                  'journalctl -u sshd' if neither exists)
#   -t THRESHOLD   Minimum failed attempts from one IP to flag as
#                  suspicious (default: 5)
#   -s SINCE       Time window for journalctl fallback, e.g. "today",
#                  "24 hours ago", "7 days ago" (default: "24 hours ago").
#                  Ignored when reading a plain-text log file.
#   -b FILE        Write flagged IPs (one per line, no other text) to
#                  FILE — ready to feed into 'fail2ban-client', an
#                  iptables script, or a firewall deny-list.
#   -o FILE        Also write the full human-readable report to a text file
#   -h             Show this help
#
# Severity levels (failed attempts from a single IP):
#   5-9    = LOW
#   10-24  = MEDIUM
#   25-99  = HIGH
#   100+   = CRITICAL
#
# Exit codes:
#   0 = no suspicious IPs found
#   1 = one or more suspicious IPs found (useful for alerting/cron)
#   2 = script error (no log source, bad args)

set -uo pipefail

LOGFILE=""
THRESHOLD=5
SINCE="24 hours ago"
BLOCKLIST_FILE=""
OUTPUT_FILE=""

usage() {
    grep '^#' "$0" | sed -n '2,26p' | sed 's/^# \{0,1\}//'
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f) LOGFILE="$2"; shift 2 ;;
        -t) THRESHOLD="$2"; shift 2 ;;
        -s) SINCE="$2"; shift 2 ;;
        -b) BLOCKLIST_FILE="$2"; shift 2 ;;
        -o) OUTPUT_FILE="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown argument: $1" >&2; usage ;;
    esac
done

if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]]; then
    echo "Error: -t must be a positive integer." >&2
    exit 2
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
        exit 2
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
    exit 2
fi

if [[ ! -s "$raw_log" ]]; then
    echo "Error: could not read log data (permission denied, or log/journal is empty)." >&2
    echo "Try running with sudo." >&2
    rm -f "$raw_log"
    exit 2
fi

report "========================================================"
report " SUSPICIOUS IP DETECTION REPORT"
report " Host       : $HOSTNAME_VAL"
report " Log source : $source_desc"
report " Threshold  : $THRESHOLD+ failed attempts"
report " Generated  : $REPORT_DATE"
report "========================================================"
report ""

# --- Extract failed attempts with IPs ---
failed_lines=$(mktemp)
grep -E "Failed password|Invalid user" "$raw_log" > "$failed_lines" 2>/dev/null

ip_list=$(mktemp)
grep -oE "from ([0-9]{1,3}\.){3}[0-9]{1,3}" "$failed_lines" | awk '{print $2}' > "$ip_list"

total_failed=$(wc -l < "$failed_lines" | xargs)
total_ips=$(sort -u "$ip_list" | wc -l | xargs)

report "Total failed login attempts scanned : $total_failed"
report "Unique source IP addresses          : $total_ips"
report ""

if [[ ! -s "$ip_list" ]]; then
    report "No IP addresses could be extracted — nothing to analyze."
    rm -f "$raw_log" "$failed_lines" "$ip_list"
    exit 0
fi

# --- Build counted, sorted IP list and classify severity ---
counted_ips=$(mktemp)
sort "$ip_list" | uniq -c | sort -rn > "$counted_ips"

flagged_tmp=$(mktemp)
suspicious_count=0

report "---- SUSPICIOUS IP ADDRESSES (>= $THRESHOLD failed attempts) ----"
report ""
report "$(printf '%-8s %-18s %-10s %s' 'COUNT' 'IP ADDRESS' 'SEVERITY' 'NOTE')"
report "------------------------------------------------------------------"

while read -r count ip; do
    [[ "$count" -lt "$THRESHOLD" ]] && continue

    if   [[ "$count" -ge 100 ]]; then severity="CRITICAL"; note="Likely automated botnet/scanner"
    elif [[ "$count" -ge 25  ]]; then severity="HIGH";     note="Sustained brute-force attempt"
    elif [[ "$count" -ge 10  ]]; then severity="MEDIUM";   note="Active brute-force attempt"
    else                              severity="LOW";      note="Repeated failures, monitor"
    fi

    report "$(printf '%-8s %-18s %-10s %s' "$count" "$ip" "$severity" "$note")"
    echo "$ip" >> "$flagged_tmp"
    ((suspicious_count++))
done < "$counted_ips"

if [[ "$suspicious_count" -eq 0 ]]; then
    report "(none — no IP reached the $THRESHOLD-attempt threshold)"
fi

report ""
report "========================================================"
if [[ "$suspicious_count" -eq 0 ]]; then
    report " ✅ RESULT: No suspicious IPs detected."
else
    report " 🚨 RESULT: $suspicious_count suspicious IP(s) detected — see above."
fi
report "========================================================"

# --- Write blocklist file if requested ---
if [[ -n "$BLOCKLIST_FILE" ]]; then
    if [[ "$suspicious_count" -gt 0 ]]; then
        sort -u "$flagged_tmp" > "$BLOCKLIST_FILE"
        echo ""
        echo "Blocklist written to: $BLOCKLIST_FILE ($suspicious_count IP(s))"
        echo "Example usage:"
        echo "  iptables: while read -r ip; do iptables -A INPUT -s \"\$ip\" -j DROP; done < $BLOCKLIST_FILE"
        echo "  fail2ban: while read -r ip; do fail2ban-client set sshd banip \"\$ip\"; done < $BLOCKLIST_FILE"
    else
        > "$BLOCKLIST_FILE"
        echo ""
        echo "Blocklist file created but empty (no suspicious IPs): $BLOCKLIST_FILE"
    fi
fi

[[ -n "$OUTPUT_FILE" ]] && echo "" && echo "Report saved to: $OUTPUT_FILE"

rm -f "$raw_log" "$failed_lines" "$ip_list" "$counted_ips" "$flagged_tmp"

[[ "$suspicious_count" -eq 0 ]] && exit 0 || exit 1
