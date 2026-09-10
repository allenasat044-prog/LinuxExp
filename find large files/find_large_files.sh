#!/bin/bash
#
# find_large_files.sh
#
# Scans a directory tree for files larger than a specified size and
# reports their location and size, sorted largest-first. Useful for
# quickly finding what's eating up disk space on a server.
#
# Usage:
#   ./find_large_files.sh [-p PATH] [-s SIZE] [-n COUNT] [-o output.txt]
#
#   -p PATH     Directory to scan (default: /)
#   -s SIZE     Minimum file size to report, e.g. 100M, 1G, 500k (default: 100M)
#               Uses 'find -size' suffixes: k=KB, M=MB, G=GB
#   -n COUNT    Limit output to the top COUNT largest files (default: show all)
#   -o FILE     Also write results to a text file
#   -h          Show this help
#
# Notes:
#   - Run with sudo for a full system scan, otherwise you'll only see
#     files you have read permission for (and get permission-denied
#     noise suppressed to stderr, not mixed into results).
#   - Scanning '/' can take a while on large filesystems; narrow -p to
#     a specific directory (e.g. /var, /home) for faster targeted checks.

set -uo pipefail

SCAN_PATH="/"
MIN_SIZE="100M"
TOP_N=""
OUTPUT_FILE=""

usage() {
    grep '^#' "$0" | sed -n '2,20p' | sed 's/^# \{0,1\}//'
    exit 1
}

while getopts "p:s:n:o:h" opt; do
    case "$opt" in
        p) SCAN_PATH="$OPTARG" ;;
        s) MIN_SIZE="$OPTARG" ;;
        n) TOP_N="$OPTARG" ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

if [[ ! -d "$SCAN_PATH" ]]; then
    echo "Error: path not found or not a directory: $SCAN_PATH" >&2
    exit 1
fi

if [[ -n "$TOP_N" ]] && ! [[ "$TOP_N" =~ ^[0-9]+$ ]]; then
    echo "Error: -n must be a positive integer." >&2
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

report "========================================================"
report " LARGE FILE DETECTION REPORT"
report " Path scanned : $SCAN_PATH"
report " Min size     : $MIN_SIZE"
report " Generated    : $REPORT_DATE"
report "========================================================"
report ""

# find + size + sort, permission-denied errors sent to /dev/null so they
# don't clutter the report (run with sudo for a complete scan)
tmp_results=$(mktemp)

# Portable across BSD find (macOS) and GNU find (Linux): use -exec stat
# instead of GNU-only -printf, since BSD find silently rejects -printf.
if stat -f%z / >/dev/null 2>&1; then
    # BSD stat (macOS)
    find "$SCAN_PATH" -xdev -type f -size "+${MIN_SIZE}" -exec stat -f '%z	%N' {} \; 2>/dev/null | sort -rn > "$tmp_results"
else
    # GNU stat (Linux)
    find "$SCAN_PATH" -xdev -type f -size "+${MIN_SIZE}" -exec stat -c '%s	%n' {} \; 2>/dev/null | sort -rn > "$tmp_results"
fi

file_count=$(wc -l < "$tmp_results" | xargs)

if [[ "$file_count" -eq 0 ]]; then
    report "No files larger than $MIN_SIZE found under $SCAN_PATH."
    rm -f "$tmp_results"
    exit 0
fi

report "Found $file_count file(s) larger than $MIN_SIZE:"
report ""
report "$(printf '%-12s %s' 'SIZE' 'PATH')"
report "------------------------------------------------------------"

display_lines="$tmp_results"
if [[ -n "$TOP_N" ]]; then
    display_lines=$(mktemp)
    head -n "$TOP_N" "$tmp_results" > "$display_lines"
fi

total_size_bytes=0
while IFS=$'\t' read -r size_bytes filepath; do
    human_size=$(numfmt --to=iec --suffix=B "$size_bytes" 2>/dev/null || echo "${size_bytes}B")
    report "$(printf '%-12s %s' "$human_size" "$filepath")"
    total_size_bytes=$((total_size_bytes + size_bytes))
done < "$display_lines"

report ""
total_human=$(numfmt --to=iec --suffix=B "$total_size_bytes" 2>/dev/null || echo "${total_size_bytes}B")
if [[ -n "$TOP_N" ]]; then
    report "Shown: top $TOP_N of $file_count matching file(s), totaling $total_human"
else
    report "Total: $file_count file(s), $total_human combined"
fi

report ""
report "========================================================"
report " END OF REPORT"
report "========================================================"

[[ -n "$OUTPUT_FILE" ]] && echo "" && echo "Report saved to: $OUTPUT_FILE"

rm -f "$tmp_results"
[[ -n "$TOP_N" ]] && rm -f "$display_lines"

exit 0
