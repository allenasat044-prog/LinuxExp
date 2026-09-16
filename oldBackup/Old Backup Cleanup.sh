#!/bin/bash
#
# Old Backup Cleanup.sh
#
# Identifies and optionally deletes backup files older than a specified
# number of days, while guaranteeing a minimum number of recent backups
# are always retained (so you never end up with zero backups, even if
# every file is older than the threshold).
#
# Usage:
#   ./"Old Backup Cleanup.sh" -d BACKUP_DIR -a DAYS [-n PATTERN] [-k MIN_KEEP] [--delete] [-o output.txt]
#
#   -d BACKUP_DIR   Directory containing backup files (required)
#   -a DAYS         Delete backups older than this many days (required)
#   -n PATTERN      Only consider files matching this pattern
#                   (default: "*.tar.gz")
#   -k MIN_KEEP     Always retain at least this many of the most recent
#                   backups regardless of age (default: 3). This is a
#                   safety net against deleting your entire backup set.
#   --delete        Actually delete. Without it, runs as a DRY RUN and
#                   only reports what would be removed (default, safe).
#   -o FILE         Also write the report to a text file
#   -h              Show this help
#
# Safety:
#   - Dry-run by default; nothing is deleted unless --delete is passed.
#   - -k guarantees a minimum number of recent backups survive.
#   - Only touches regular files matching the pattern, never directories.
#
# Exit codes: 0 = success, 1 = error

set -uo pipefail

BACKUP_DIR=""
AGE_DAYS=""
NAME_PATTERN="*.tar.gz"
MIN_KEEP=3
DO_DELETE=false
OUTPUT_FILE=""

usage() {
    grep '^#' "$0" | sed -n '2,26p' | sed 's/^# \{0,1\}//'
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d) BACKUP_DIR="$2"; shift 2 ;;
        -a) AGE_DAYS="$2"; shift 2 ;;
        -n) NAME_PATTERN="$2"; shift 2 ;;
        -k) MIN_KEEP="$2"; shift 2 ;;
        --delete) DO_DELETE=true; shift ;;
        -o) OUTPUT_FILE="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown argument: $1" >&2; usage ;;
    esac
done

if [[ -z "$BACKUP_DIR" || -z "$AGE_DAYS" ]]; then
    echo "Error: -d BACKUP_DIR and -a DAYS are required." >&2
    usage
fi

if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "Error: directory not found: $BACKUP_DIR" >&2
    exit 1
fi

if ! [[ "$AGE_DAYS" =~ ^[0-9]+$ ]]; then
    echo "Error: -a must be a non-negative integer (days)." >&2
    exit 1
fi

if ! [[ "$MIN_KEEP" =~ ^[0-9]+$ ]]; then
    echo "Error: -k must be a non-negative integer." >&2
    exit 1
fi

BACKUP_DIR=$(cd "$BACKUP_DIR" && pwd)

# Safety guard: refuse top-level/home dirs when deleting
DANGEROUS_PATHS=("/" "/home" "/etc" "/usr" "/var" "/bin" "/sbin" "/System" "/Users" "$HOME")
if [[ "$DO_DELETE" == true ]]; then
    for dangerous in "${DANGEROUS_PATHS[@]}"; do
        if [[ "$BACKUP_DIR" == "$dangerous" ]]; then
            echo "Error: refusing to delete directly from '$BACKUP_DIR'. Point -d at a" >&2
            echo "dedicated backup subfolder instead." >&2
            exit 1
        fi
    done
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
MODE_LABEL="DRY RUN (nothing will be deleted)"
[[ "$DO_DELETE" == true ]] && MODE_LABEL="LIVE DELETE"

report "========================================================"
report " OLD BACKUP CLEANUP"
report " Directory   : $BACKUP_DIR"
report " Pattern     : $NAME_PATTERN"
report " Older than  : $AGE_DAYS day(s)"
report " Always keep : $MIN_KEEP most recent"
report " Mode        : $MODE_LABEL"
report " Generated   : $REPORT_DATE"
report "========================================================"
report ""

# Detect BSD (macOS) vs GNU (Linux) stat
if stat -f%z / >/dev/null 2>&1; then
    STAT_MTIME='stat -f %m'
    STAT_SIZE='stat -f %z'
    IS_BSD=true
else
    STAT_MTIME='stat -c %Y'
    STAT_SIZE='stat -c %s'
    IS_BSD=false
fi

# Gather all matching backups, newest first: "mtime<TAB>path"
all_backups=$(mktemp)
if [[ "$IS_BSD" == true ]]; then
    find "$BACKUP_DIR" -maxdepth 1 -type f -name "$NAME_PATTERN" -exec stat -f '%m	%N' {} \; 2>/dev/null | sort -rn > "$all_backups"
else
    find "$BACKUP_DIR" -maxdepth 1 -type f -name "$NAME_PATTERN" -exec stat -c '%Y	%n' {} \; 2>/dev/null | sort -rn > "$all_backups"
fi

total_count=$(wc -l < "$all_backups" | xargs)

if [[ "$total_count" -eq 0 ]]; then
    report "No backup files matching '$NAME_PATTERN' found in $BACKUP_DIR."
    rm -f "$all_backups"
    exit 0
fi

report "Total backups found: $total_count"
report ""

now_epoch=$(date +%s)
cutoff_epoch=$(( now_epoch - (AGE_DAYS * 86400) ))

retained_count=0
deleted_count=0
freed_bytes=0
protected_count=0

index=0
while IFS=$'\t' read -r mtime filepath; do
    ((index++))

    if [[ "$IS_BSD" == true ]]; then
        mtime_display=$(date -r "$mtime" '+%Y-%m-%d %H:%M')
        size_bytes=$(stat -f%z "$filepath" 2>/dev/null || echo 0)
    else
        mtime_display=$(date -d "@$mtime" '+%Y-%m-%d %H:%M')
        size_bytes=$(stat -c%s "$filepath" 2>/dev/null || echo 0)
    fi
    human_size=$(numfmt --to=iec --suffix=B "$size_bytes" 2>/dev/null || echo "${size_bytes}B")

    age_days=$(( (now_epoch - mtime) / 86400 ))

    # Protected by the minimum-keep rule?
    if [[ "$index" -le "$MIN_KEEP" ]]; then
        report "  [KEEP - recent] $(basename "$filepath")  ($human_size, ${age_days}d old, $mtime_display)"
        ((retained_count++))
        ((protected_count++))
        continue
    fi

    if [[ "$mtime" -lt "$cutoff_epoch" ]]; then
        if [[ "$DO_DELETE" == true ]]; then
            if rm -f "$filepath" 2>/dev/null; then
                report "  [DELETED]      $(basename "$filepath")  ($human_size, ${age_days}d old, $mtime_display)"
                ((deleted_count++))
                freed_bytes=$((freed_bytes + size_bytes))
            else
                report "  [ERROR]        $(basename "$filepath") — could not delete (permissions?)"
            fi
        else
            report "  [WOULD DELETE] $(basename "$filepath")  ($human_size, ${age_days}d old, $mtime_display)"
            ((deleted_count++))
            freed_bytes=$((freed_bytes + size_bytes))
        fi
    else
        report "  [KEEP - fresh] $(basename "$filepath")  ($human_size, ${age_days}d old, $mtime_display)"
        ((retained_count++))
    fi

done < "$all_backups"

freed_human=$(numfmt --to=iec --suffix=B "$freed_bytes" 2>/dev/null || echo "${freed_bytes}B")

report ""
report "--------------------------------------------------------"
report "Retained : $retained_count backup(s)  ($protected_count protected by -k $MIN_KEEP)"
if [[ "$DO_DELETE" == true ]]; then
    report "Deleted  : $deleted_count backup(s), freeing $freed_human"
else
    report "Would delete: $deleted_count backup(s), freeing $freed_human"
    report ""
    report "ℹ️  DRY RUN — re-run with --delete to actually remove these."
fi
report "--------------------------------------------------------"
report ""
report "========================================================"
report " END OF REPORT"
report "========================================================"

[[ -n "$OUTPUT_FILE" ]] && echo "" && echo "Report saved to: $OUTPUT_FILE"

rm -f "$all_backups"
exit 0
