#!/bin/bash
set -uo pipefail

DAYS=30
MIN_UID=500
OUTPUT_FILE=""
INCLUDE_ALL=false

usage() {
    echo "Usage: $0 [-d DAYS] [-m MIN_UID] [-o output.csv] [-a]"
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

if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: this script is for macOS only." >&2
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "Warning: not running as root/sudo — 'last' may show incomplete results." >&2
fi

NOW_EPOCH=$(date +%s)

echo "Scanning for macOS accounts inactive for more than $DAYS day(s)..."
echo "-----------------------------------------------------------------------------------"
printf "%-15s %-8s %-20s %-15s %s\n" "USERNAME" "UID" "LAST LOGIN" "DAYS INACTIVE" "STATUS"
echo "-----------------------------------------------------------------------------------"

if [[ -n "$OUTPUT_FILE" ]]; then
    echo "username,uid,last_login,days_inactive,status" > "$OUTPUT_FILE"
fi

inactive_count=0
never_logged_in_count=0
total_checked=0

while read -r username uid; do
    [[ -z "$username" ]] && continue

    if [[ "$INCLUDE_ALL" == false ]]; then
        [[ "$username" == _* ]] && continue
        [[ "$uid" -lt "$MIN_UID" ]] && continue
        [[ "$username" == "nobody" || "$username" == "daemon" || "$username" == "root" ]] && continue
    fi

    ((total_checked++))

    last_line=$(last -1 "$username" 2>/dev/null | head -n 1)

    if [[ -z "$last_line" || "$last_line" == wtmp\ begins* ]]; then
        printf "%-15s %-8s %-20s %-15s %s\n" "$username" "$uid" "never" "N/A" "NEVER LOGGED IN"
        [[ -n "$OUTPUT_FILE" ]] && echo "$username,$uid,never,N/A,NEVER_LOGGED_IN" >> "$OUTPUT_FILE"
        ((never_logged_in_count++))
        continue
    fi

    date_str=$(echo "$last_line" | awk '{print $4, $5, $6, $7}')
    last_login_epoch=$(date -j -f "%b %d %H:%M %Y" "$(echo "$date_str" | awk -v y="$(date +%Y)" '{print $1, $2, $3, y}')" +%s 2>/dev/null)

    if [[ -z "$last_login_epoch" ]]; then
        last_login_epoch=$(echo "$last_line" | awk '{print $4, $5, $6}' | xargs -I{} date -j -f "%b %d %H:%M" "{}" +%s 2>/dev/null)
    fi

    if [[ -z "$last_login_epoch" ]]; then
        printf "%-15s %-8s %-20s %-15s %s\n" "$username" "$uid" "unparseable" "N/A" "UNKNOWN"
        [[ -n "$OUTPUT_FILE" ]] && echo "$username,$uid,unparseable,N/A,UNKNOWN" >> "$OUTPUT_FILE"
        continue
    fi

    days_inactive=$(( (NOW_EPOCH - last_login_epoch) / 86400 ))
    last_login_display=$(date -j -f "%s" "$last_login_epoch" '+%Y-%m-%d %H:%M' 2>/dev/null)

    if [[ "$days_inactive" -ge "$DAYS" ]]; then
        printf "%-15s %-8s %-20s %-15s %s\n" "$username" "$uid" "$last_login_display" "$days_inactive" "INACTIVE"
        [[ -n "$OUTPUT_FILE" ]] && echo "$username,$uid,$last_login_display,$days_inactive,INACTIVE" >> "$OUTPUT_FILE"
        ((inactive_count++))
    fi

done < <(dscl . -list /Users UniqueID | awk '{print $1, $2}')

echo "-----------------------------------------------------------------------------------"
echo "Accounts checked      : $total_checked"
echo "Inactive (>= $DAYS days): $inactive_count"
echo "Never logged in       : $never_logged_in_count"
[[ -n "$OUTPUT_FILE" ]] && echo "Results written to: $OUTPUT_FILE"

exit 0
