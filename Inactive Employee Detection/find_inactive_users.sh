#!/bin/bash
#
# find_inactive_users.sh
#
# Identifies local user accounts that have not logged in within a given
# number of days (default 30), or have never logged in at all.
# Useful for periodic account audits / offboarding checks.
#
# Usage:
#   ./find_inactive_users.sh [-d DAYS] [-m MIN_UID] [-o output.csv] [-a]
#
#   -d DAYS      Inactivity threshold in days (default: 30)
#   -m MIN_UID   Minimum UID to consider a "real" human account (default: 1000)
#                Lower UIDs (system/service accounts) are skipped unless -a is set
#   -o FILE      Also write results to a CSV file
#   -a           Include ALL accounts (system + service), ignore -m filter
#   -h           Show this help
#
# Requires: lastlog (part of shadow-utils / login-utils, present on nearly
#           every mainstream distro by default)

set -uo pipefail

# ---- Defaults ----
DAYS=30
MIN_UID=1000
OUTPUT_FILE=""
INCLUDE_ALL=false

usage() {
    grep '^#' "$0" | sed -n '2,20p' | sed 's/^# \{0,1\}//'
    exit 1
}

while getopts "d:m:o:ah" opt; do
    case "$opt" in
        d) DAYS="$OPTARG" ;;
        m) MIN_UID="$OPTARG" ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        a) INCLUDE_ALL=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

if ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
    echo "Error: -d must be a positive integer (days)." >&2
    exit 1
fi

if ! command -v lastlog >/dev/null 2>&1; then
    echo "Error: 'lastlog' command not found. Install shadow-utils / login-utils package." >&2
    exit 1
fi

NOW_EPOCH=$(date +%s)
THRESHOLD_SECONDS=$(( DAYS * 86400 ))

echo "Scanning for accounts inactive for more than $DAYS day(s)..."
echo "-----------------------------------------------------------------------------------"
printf "%-15s %-10s %-20s %-15s %s\n" "USERNAME" "UID" "LAST LOGIN" "DAYS INACTIVE" "STATUS"
echo "-----------------------------------------------------------------------------------"

# CSV header if requested
if [[ -n "$OUTPUT_FILE" ]]; then
    echo "username,uid,last_login,days_inactive,status" > "$OUTPUT_FILE"
fi

inactive_count=0
never_logged_in_count=0
total_checked=0

# Iterate over real accounts from /etc/passwd
while IFS=: read -r username _ uid _ _ home shell; do

    # Skip accounts below the UID filter unless -a was given
    if [[ "$INCLUDE_ALL" == false && "$uid" -lt "$MIN_UID" ]]; then
        continue
    fi

    # Skip common non-login shells (nologin/false) unless -a was given
    if [[ "$INCLUDE_ALL" == false ]]; then
        case "$shell" in
            */nologin|*/false) continue ;;
        esac
    fi

    ((total_checked++))

    # Query lastlog for this specific user
    ll_output=$(lastlog -u "$username" 2>/dev/null | tail -n 1)

    if echo "$ll_output" | grep -q "Never logged in"; then
        printf "%-15s %-10s %-20s %-15s %s\n" "$username" "$uid" "never" "N/A" "NEVER LOGGED IN"
        [[ -n "$OUTPUT_FILE" ]] && echo "$username,$uid,never,N/A,NEVER_LOGGED_IN" >> "$OUTPUT_FILE"
        ((never_logged_in_count++))
        continue
    fi

    # Extract the last-login date portion (lastlog's fixed-width output
    # after the port/from columns); fall back gracefully if parsing fails
    last_login_str=$(echo "$ll_output" | awk '{for(i=4;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')

    if [[ -z "$last_login_str" ]]; then
        printf "%-15s %-10s %-20s %-15s %s\n" "$username" "$uid" "unknown" "N/A" "UNKNOWN"
        [[ -n "$OUTPUT_FILE" ]] && echo "$username,$uid,unknown,N/A,UNKNOWN" >> "$OUTPUT_FILE"
        continue
    fi

    last_login_epoch=$(date -d "$last_login_str" +%s 2>/dev/null)

    if [[ -z "$last_login_epoch" ]]; then
        printf "%-15s %-10s %-20s %-15s %s\n" "$username" "$uid" "unparseable" "N/A" "UNKNOWN"
        [[ -n "$OUTPUT_FILE" ]] && echo "$username,$uid,unparseable,N/A,UNKNOWN" >> "$OUTPUT_FILE"
        continue
    fi

    days_inactive=$(( (NOW_EPOCH - last_login_epoch) / 86400 ))
    last_login_display=$(date -d "@$last_login_epoch" '+%Y-%m-%d %H:%M')

    if [[ "$days_inactive" -ge "$DAYS" ]]; then
        printf "%-15s %-10s %-20s %-15s %s\n" "$username" "$uid" "$last_login_display" "$days_inactive" "INACTIVE"
        [[ -n "$OUTPUT_FILE" ]] && echo "$username,$uid,$last_login_display,$days_inactive,INACTIVE" >> "$OUTPUT_FILE"
        ((inactive_count++))
    fi

done < /etc/passwd

echo "-----------------------------------------------------------------------------------"
echo "Accounts checked      : $total_checked"
echo "Inactive (>= $DAYS days): $inactive_count"
echo "Never logged in       : $never_logged_in_count"

if [[ -n "$OUTPUT_FILE" ]]; then
    echo "Results written to: $OUTPUT_FILE"
fi

exit 0
