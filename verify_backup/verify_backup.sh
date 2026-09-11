#!/bin/bash
#
# verify_backup.sh
#
# Checks whether the latest backup in a directory was created successfully:
# confirms it exists, reports its size and age, and runs an integrity
# check on the archive. Designed to pair with backup_project.sh, but works
# on any directory of .tar.gz / .tar / .zip backup files.
#
# Usage:
#   ./verify_backup.sh -d BACKUP_DIR [-n NAME_PATTERN] [-m MAX_AGE_HOURS] [-o output.txt]
#
#   -d BACKUP_DIR      Directory containing backup archives (required)
#   -n NAME_PATTERN     Only consider files matching this pattern
#                       (e.g. "myproject_*.tar.gz"; default: "*.tar.gz")
#   -m MAX_AGE_HOURS    Flag as stale if the latest backup is older than
#                       this many hours (default: 26 — allows some slack
#                       for a daily backup job)
#   -o FILE             Also write the report to a text file
#   -h                  Show this help
#
# Exit codes:
#   0 = backup found, recent, and passes integrity check
#   1 = backup missing, stale, empty, or fails integrity check

set -uo pipefail

BACKUP_DIR=""
NAME_PATTERN="*.tar.gz"
MAX_AGE_HOURS=26
OUTPUT_FILE=""

usage() {
    grep '^#' "$0" | sed -n '2,18p' | sed 's/^# \{0,1\}//'
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d) BACKUP_DIR="$2"; shift 2 ;;
        -n) NAME_PATTERN="$2"; shift 2 ;;
        -m) MAX_AGE_HOURS="$2"; shift 2 ;;
        -o) OUTPUT_FILE="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown argument: $1" >&2; usage ;;
    esac
done

if [[ -z "$BACKUP_DIR" ]]; then
    echo "Error: -d BACKUP_DIR is required." >&2
    usage
fi

if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "Error: directory not found: $BACKUP_DIR" >&2
    exit 1
fi

if ! [[ "$MAX_AGE_HOURS" =~ ^[0-9]+$ ]]; then
    echo "Error: -m must be a positive integer (hours)." >&2
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

BACKUP_DIR=$(cd "$BACKUP_DIR" && pwd)
REPORT_DATE=$(date '+%Y-%m-%d %H:%M:%S %Z')

report "========================================================"
report " BACKUP VERIFICATION REPORT"
report " Directory  : $BACKUP_DIR"
report " Pattern    : $NAME_PATTERN"
report " Max age    : ${MAX_AGE_HOURS}h"
report " Generated  : $REPORT_DATE"
report "========================================================"
report ""

# Find the most recently modified file matching the pattern
latest_backup=""
if stat -f%z / >/dev/null 2>&1; then
    # macOS/BSD: use -exec stat with mtime for sortable output
    latest_backup=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "$NAME_PATTERN" -exec stat -f '%m %N' {} \; 2>/dev/null | sort -rn | head -n1 | cut -d' ' -f2-)
else
    latest_backup=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "$NAME_PATTERN" -exec stat -c '%Y %n' {} \; 2>/dev/null | sort -rn | head -n1 | cut -d' ' -f2-)
fi

if [[ -z "$latest_backup" ]]; then
    report "❌ STATUS: FAIL"
    report "No backup files matching '$NAME_PATTERN' found in $BACKUP_DIR."
    report ""
    report "========================================================"
    [[ -n "$OUTPUT_FILE" ]] && echo "" && echo "Report saved to: $OUTPUT_FILE"
    exit 1
fi

report "Latest backup found: $latest_backup"
report ""

# --- Size check ---
if stat -f%z / >/dev/null 2>&1; then
    size_bytes=$(stat -f%z "$latest_backup")
    mtime_epoch=$(stat -f%m "$latest_backup")
else
    size_bytes=$(stat -c%s "$latest_backup")
    mtime_epoch=$(stat -c%Y "$latest_backup")
fi
human_size=$(numfmt --to=iec --suffix=B "$size_bytes" 2>/dev/null || echo "${size_bytes}B")

report "---- SIZE ----"
report "Size: $human_size ($size_bytes bytes)"
size_ok=true
if [[ "$size_bytes" -eq 0 ]]; then
    report "❌ WARNING: backup file is 0 bytes — likely a failed or empty backup."
    size_ok=false
fi
report ""

# --- Age check ---
now_epoch=$(date +%s)
age_seconds=$(( now_epoch - mtime_epoch ))
age_hours=$(( age_seconds / 3600 ))
age_display_h=$(( age_seconds / 3600 ))
age_display_m=$(( (age_seconds % 3600) / 60 ))

report "---- AGE ----"
if stat -f%z / >/dev/null 2>&1; then
    mtime_display=$(date -r "$mtime_epoch" '+%Y-%m-%d %H:%M:%S')
else
    mtime_display=$(date -d "@$mtime_epoch" '+%Y-%m-%d %H:%M:%S')
fi
report "Created: $mtime_display"
report "Age: ${age_display_h}h ${age_display_m}m"

age_ok=true
if [[ "$age_hours" -ge "$MAX_AGE_HOURS" ]]; then
    report "❌ WARNING: backup is older than the ${MAX_AGE_HOURS}h threshold — it may be stale."
    age_ok=false
fi
report ""

# --- Integrity check ---
report "---- INTEGRITY ----"
integrity_ok=true
case "$latest_backup" in
    *.tar.gz|*.tgz)
        if tar -tzf "$latest_backup" >/dev/null 2>&1; then
            report "✅ Archive integrity check passed (tar -tzf)."
        else
            report "❌ Archive integrity check FAILED — file may be corrupt or incomplete."
            integrity_ok=false
        fi
        ;;
    *.tar)
        if tar -tf "$latest_backup" >/dev/null 2>&1; then
            report "✅ Archive integrity check passed (tar -tf)."
        else
            report "❌ Archive integrity check FAILED — file may be corrupt or incomplete."
            integrity_ok=false
        fi
        ;;
    *.zip)
        if command -v unzip >/dev/null 2>&1 && unzip -tq "$latest_backup" >/dev/null 2>&1; then
            report "✅ Archive integrity check passed (unzip -t)."
        else
            report "❌ Archive integrity check FAILED, or 'unzip' not available."
            integrity_ok=false
        fi
        ;;
    *.gz)
        if gzip -t "$latest_backup" >/dev/null 2>&1; then
            report "✅ Archive integrity check passed (gzip -t)."
        else
            report "❌ Archive integrity check FAILED — file may be corrupt."
            integrity_ok=false
        fi
        ;;
    *)
        report "ℹ️  No integrity check available for this file type — skipped."
        ;;
esac
report ""

# --- Overall status ---
report "========================================================"
if [[ "$size_ok" == true && "$age_ok" == true && "$integrity_ok" == true ]]; then
    report " ✅ OVERALL STATUS: PASS — latest backup looks healthy."
    overall_exit=0
else
    report " ❌ OVERALL STATUS: FAIL — see warnings above."
    overall_exit=1
fi
report "========================================================"

[[ -n "$OUTPUT_FILE" ]] && echo "" && echo "Report saved to: $OUTPUT_FILE"

exit $overall_exit
