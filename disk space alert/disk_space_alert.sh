#!/bin/bash
#
# disk_space_alert.sh
#
# Checks all mounted filesystems and warns about any that have crossed
# a usage threshold (default 80%). Useful as a daily cron check or
# manual pre-shift sanity check.
#
# Usage:
#   ./disk_space_alert.sh [-t THRESHOLD] [-o output.txt]
#
#   -t THRESHOLD   Usage percentage threshold to warn at (default: 80)
#   -o FILE        Also write the report to a text file
#   -h             Show this help
#
# Exit codes:
#   0 = all filesystems OK (below threshold)
#   1 = at least one filesystem is at/above threshold
#   2 = script error (bad args, df not found)

set -uo pipefail

THRESHOLD=80
OUTPUT_FILE=""

usage() {
    grep '^#' "$0" | sed -n '2,14p' | sed 's/^# \{0,1\}//'
    exit 2
}

while getopts "t:o:h" opt; do
    case "$opt" in
        t) THRESHOLD="$OPTARG" ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]] || [[ "$THRESHOLD" -lt 1 || "$THRESHOLD" -gt 100 ]]; then
    echo "Error: -t must be an integer between 1 and 100." >&2
    exit 2
fi

if ! command -v df >/dev/null 2>&1; then
    echo "Error: 'df' command not found." >&2
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

report "========================================================"
report " DISK SPACE ALERT CHECK"
report " Host: $HOSTNAME_VAL"
report " Generated: $REPORT_DATE"
report " Threshold: ${THRESHOLD}%"
report "========================================================"
report ""

flagged_count=0
total_checked=0

# Read real filesystems only — skip pseudo/virtual mounts that don't
# represent actual disk capacity (tmpfs, overlay, squashfs, devtmpfs, etc.)
while read -r filesystem size used avail pct mount; do
    [[ "$filesystem" == "Filesystem" ]] && continue
    case "$filesystem" in
        tmpfs*|udev*|overlay*|squashfs*|devtmpfs*|shm*|none) continue ;;
    esac

    ((total_checked++))
    pct_num=${pct%\%}

    if ! [[ "$pct_num" =~ ^[0-9]+$ ]]; then
        continue
    fi

    if [[ "$pct_num" -ge "$THRESHOLD" ]]; then
        if [[ "$pct_num" -ge 95 ]]; then
            level="CRITICAL"
        else
            level="WARNING"
        fi
        report "[$level] $mount ($filesystem) is at ${pct} used — ${used} used / ${size} total, ${avail} available"
        ((flagged_count++))
    fi

done < <(df -h 2>/dev/null)

report ""
if [[ "$flagged_count" -eq 0 ]]; then
    report "✅ All $total_checked filesystem(s) are below ${THRESHOLD}% usage. No action needed."
else
    report "🚨 $flagged_count of $total_checked filesystem(s) have crossed ${THRESHOLD}% usage. Review above."
fi

report ""
report "========================================================"
report " END OF REPORT"
report "========================================================"

if [[ -n "$OUTPUT_FILE" ]]; then
    echo ""
    echo "Report saved to: $OUTPUT_FILE"
fi

[[ "$flagged_count" -eq 0 ]] && exit 0 || exit 1
