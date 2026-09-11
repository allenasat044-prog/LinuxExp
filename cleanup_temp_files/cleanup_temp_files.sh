#!/bin/bash
#
# cleanup_temp_files.sh
#
# Identifies and removes temporary files older than a specified number
# of days from a designated directory. Defaults to a safe dry-run so
# you can review what would be deleted before anything actually happens.
#
# Usage:
#   ./cleanup_temp_files.sh -p PATH -d DAYS [-x PATTERN] [--delete] [-o output.txt]
#
#   -p PATH      Directory to clean (required)
#   -d DAYS      Delete files older than this many days (required)
#   -x PATTERN   Only match files with this name pattern, e.g. "*.tmp" or "*.log"
#                (default: * — all files). Can be given multiple times.
#   --delete     Actually delete the files. Without this flag, the script
#                only lists what WOULD be deleted (dry-run — this is the
#                default and safe behavior).
#   -o FILE      Also write the report to a text file
#   -h           Show this help
#
# Safety:
#   - Dry-run is the default. Nothing is deleted unless you pass --delete.
#   - Refuses to run against dangerous root-level paths (/, /home, /etc,
#     /usr, /var, /bin, /sbin, /System) even with --delete, to prevent
#     an accidental wipe. Point it at a specific temp directory instead.
#   - Only matches regular files (-type f), never directories.

set -uo pipefail

SCAN_PATH=""
DAYS=""
PATTERNS=()
DO_DELETE=false
OUTPUT_FILE=""

usage() {
    grep '^#' "$0" | sed -n '2,20p' | sed 's/^# \{0,1\}//'
    exit 1
}

# Manual arg parsing to support the --delete long flag alongside getopts-style short flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p) SCAN_PATH="$2"; shift 2 ;;
        -d) DAYS="$2"; shift 2 ;;
        -x) PATTERNS+=("$2"); shift 2 ;;
        -o) OUTPUT_FILE="$2"; shift 2 ;;
        --delete) DO_DELETE=true; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown argument: $1" >&2; usage ;;
    esac
done

if [[ -z "$SCAN_PATH" || -z "$DAYS" ]]; then
    echo "Error: -p PATH and -d DAYS are required." >&2
    usage
fi

if [[ ! -d "$SCAN_PATH" ]]; then
    echo "Error: path not found or not a directory: $SCAN_PATH" >&2
    exit 1
fi

if ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
    echo "Error: -d must be a non-negative integer." >&2
    exit 1
fi

# Safety guard: refuse dangerous top-level paths when --delete is set
DANGEROUS_PATHS=("/" "/home" "/etc" "/usr" "/var" "/bin" "/sbin" "/System" "/Users" "$HOME")
resolved_path=$(cd "$SCAN_PATH" 2>/dev/null && pwd)
if [[ "$DO_DELETE" == true ]]; then
    for dangerous in "${DANGEROUS_PATHS[@]}"; do
        if [[ "$resolved_path" == "$dangerous" ]]; then
            echo "Error: refusing to delete directly from '$resolved_path' — this looks like a" >&2
            echo "top-level or home directory. Point -p at a specific temp/cache subfolder instead." >&2
            exit 1
        fi
    done
fi

[[ ${#PATTERNS[@]} -eq 0 ]] && PATTERNS=("*")

report() {
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$1" | tee -a "$OUTPUT_FILE"
    else
        echo "$1"
    fi
}

[[ -n "$OUTPUT_FILE" ]] && > "$OUTPUT_FILE"

REPORT_DATE=$(date '+%Y-%m-%d %H:%M:%S %Z')
MODE_LABEL="DRY RUN (no files will be deleted)"
[[ "$DO_DELETE" == true ]] && MODE_LABEL="LIVE DELETE"

report "========================================================"
report " TEMPORARY FILE CLEANUP"
report " Path       : $resolved_path"
report " Older than : $DAYS day(s)"
report " Patterns   : ${PATTERNS[*]}"
report " Mode       : $MODE_LABEL"
report " Generated  : $REPORT_DATE"
report "========================================================"
report ""

# Build find's -name arguments for multiple patterns: ( -name P1 -o -name P2 ... )
name_args=()
for i in "${!PATTERNS[@]}"; do
    [[ $i -gt 0 ]] && name_args+=("-o")
    name_args+=("-name" "${PATTERNS[$i]}")
done

tmp_results=$(mktemp)
find "$resolved_path" -xdev -type f \( "${name_args[@]}" \) -mtime "+${DAYS}" 2>/dev/null > "$tmp_results"

file_count=$(wc -l < "$tmp_results" | xargs)

if [[ "$file_count" -eq 0 ]]; then
    report "No files older than $DAYS day(s) matching pattern(s) found in $resolved_path."
    rm -f "$tmp_results"
    exit 0
fi

report "Found $file_count file(s) older than $DAYS day(s):"
report ""

total_size_bytes=0
while IFS= read -r filepath; do
    if stat -f%z / >/dev/null 2>&1; then
        size_bytes=$(stat -f%z "$filepath" 2>/dev/null || echo 0)
    else
        size_bytes=$(stat -c%s "$filepath" 2>/dev/null || echo 0)
    fi
    human_size=$(numfmt --to=iec --suffix=B "$size_bytes" 2>/dev/null || echo "${size_bytes}B")
    report "  [$human_size] $filepath"
    total_size_bytes=$((total_size_bytes + size_bytes))

    if [[ "$DO_DELETE" == true ]]; then
        if rm -f "$filepath" 2>/dev/null; then
            :
        else
            report "    -> ERROR: failed to delete this file (permissions?)"
        fi
    fi
done < "$tmp_results"

total_human=$(numfmt --to=iec --suffix=B "$total_size_bytes" 2>/dev/null || echo "${total_size_bytes}B")

report ""
if [[ "$DO_DELETE" == true ]]; then
    report "✅ Deleted $file_count file(s), freeing approximately $total_human."
else
    report "ℹ️  DRY RUN: $file_count file(s) totaling $total_human would be deleted."
    report "    Re-run with --delete to actually remove them."
fi

report ""
report "========================================================"
report " END OF REPORT"
report "========================================================"

[[ -n "$OUTPUT_FILE" ]] && echo "" && echo "Report saved to: $OUTPUT_FILE"

rm -f "$tmp_results"
exit 0
