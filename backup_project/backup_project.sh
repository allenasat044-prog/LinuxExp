#!/bin/bash
#
# backup_project.sh
#
# Creates a compressed, timestamped backup (.tar.gz) of a specified
# project directory. Useful as a quick manual backup or a daily cron job.
#
# Usage:
#   ./backup_project.sh -s SOURCE_DIR -d DEST_DIR [-n NAME] [-k KEEP_COUNT] [-x EXCLUDE_PATTERN]
#
#   -s SOURCE_DIR    Directory to back up (required)
#   -d DEST_DIR      Directory to store the backup archive in (required;
#                     created automatically if it doesn't exist)
#   -n NAME          Base name for the archive (default: basename of SOURCE_DIR)
#   -k KEEP_COUNT     Keep only the N most recent backups for this NAME,
#                     deleting older ones automatically (default: keep all)
#   -x PATTERN        Exclude files/dirs matching PATTERN (e.g. "node_modules",
#                     "*.log"). Can be given multiple times.
#   -h                Show this help
#
# Output:
#   DEST_DIR/NAME_YYYYMMDD_HHMMSS.tar.gz
#
# Exit codes: 0 = success, 1 = error

set -uo pipefail

SOURCE_DIR=""
DEST_DIR=""
BACKUP_NAME=""
KEEP_COUNT=""
EXCLUDES=()

usage() {
    grep '^#' "$0" | sed -n '2,20p' | sed 's/^# \{0,1\}//'
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s) SOURCE_DIR="$2"; shift 2 ;;
        -d) DEST_DIR="$2"; shift 2 ;;
        -n) BACKUP_NAME="$2"; shift 2 ;;
        -k) KEEP_COUNT="$2"; shift 2 ;;
        -x) EXCLUDES+=("$2"); shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown argument: $1" >&2; usage ;;
    esac
done

if [[ -z "$SOURCE_DIR" || -z "$DEST_DIR" ]]; then
    echo "Error: -s SOURCE_DIR and -d DEST_DIR are required." >&2
    usage
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: source directory not found: $SOURCE_DIR" >&2
    exit 1
fi

if [[ -n "$KEEP_COUNT" ]] && ! [[ "$KEEP_COUNT" =~ ^[0-9]+$ ]]; then
    echo "Error: -k must be a positive integer." >&2
    exit 1
fi

# Resolve to absolute paths so the backup works regardless of current dir
SOURCE_DIR=$(cd "$SOURCE_DIR" && pwd)
mkdir -p "$DEST_DIR" || { echo "Error: could not create destination directory: $DEST_DIR" >&2; exit 1; }
DEST_DIR=$(cd "$DEST_DIR" && pwd)

[[ -z "$BACKUP_NAME" ]] && BACKUP_NAME=$(basename "$SOURCE_DIR")

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
ARCHIVE_FILE="${DEST_DIR}/${BACKUP_NAME}_${TIMESTAMP}.tar.gz"

# Refuse to back up a directory into itself (common footgun)
if [[ "$DEST_DIR" == "$SOURCE_DIR"* ]]; then
    echo "Error: destination directory is inside the source directory — this would" >&2
    echo "cause the backup to try to include itself. Choose a destination outside" >&2
    echo "the source tree." >&2
    exit 1
fi

echo "========================================================"
echo " DAILY BACKUP"
echo " Source      : $SOURCE_DIR"
echo " Destination : $ARCHIVE_FILE"
echo " Generated   : $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "========================================================"
echo ""

# Build tar --exclude args
tar_exclude_args=()
for pattern in "${EXCLUDES[@]:-}"; do
    [[ -n "$pattern" ]] && tar_exclude_args+=(--exclude="$pattern")
done

echo "Creating archive..."
parent_dir=$(dirname "$SOURCE_DIR")
base_name=$(basename "$SOURCE_DIR")

if tar -czf "$ARCHIVE_FILE" "${tar_exclude_args[@]}" -C "$parent_dir" "$base_name" 2>/tmp/backup_err_$$; then
    echo "✅ Backup created successfully."
else
    echo "❌ Backup failed. Error details:" >&2
    cat /tmp/backup_err_$$ >&2
    rm -f /tmp/backup_err_$$
    exit 1
fi
rm -f /tmp/backup_err_$$

# Report size and verify integrity
if stat -f%z / >/dev/null 2>&1; then
    archive_size=$(stat -f%z "$ARCHIVE_FILE")
else
    archive_size=$(stat -c%s "$ARCHIVE_FILE")
fi
human_size=$(numfmt --to=iec --suffix=B "$archive_size" 2>/dev/null || echo "${archive_size}B")

echo ""
echo "Archive     : $ARCHIVE_FILE"
echo "Size        : $human_size"

echo ""
echo "Verifying archive integrity..."
if tar -tzf "$ARCHIVE_FILE" >/dev/null 2>&1; then
    echo "✅ Archive integrity check passed."
else
    echo "⚠ WARNING: archive integrity check failed — the backup may be corrupt." >&2
fi

# Rotate old backups if -k was given
if [[ -n "$KEEP_COUNT" ]]; then
    echo ""
    echo "Applying retention policy (keep last $KEEP_COUNT for '$BACKUP_NAME')..."
    mapfile -t existing_backups < <(ls -1t "${DEST_DIR}/${BACKUP_NAME}"_*.tar.gz 2>/dev/null)
    total_existing=${#existing_backups[@]}
    if [[ "$total_existing" -gt "$KEEP_COUNT" ]]; then
        to_delete=("${existing_backups[@]:$KEEP_COUNT}")
        for old_backup in "${to_delete[@]}"; do
            rm -f "$old_backup"
            echo "  Removed old backup: $old_backup"
        done
    else
        echo "  Nothing to remove ($total_existing backup(s) present, limit is $KEEP_COUNT)."
    fi
fi

echo ""
echo "========================================================"
echo " BACKUP COMPLETE"
echo "========================================================"

exit 0
