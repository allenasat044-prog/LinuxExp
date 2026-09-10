#!/bin/bash
#
# audit_world_writable.sh
# Scans a target directory for world-writable files/directories and
# generates a timestamped audit report. Written for macOS (BSD find/stat).
#
# Usage:
#   ./audit_world_writable.sh <directory_to_scan> [output_dir]
#
# Example:
#   ./audit_world_writable.sh /Shared ~/Desktop
#
set -uo pipefail

# ---------- 0. Input validation ----------

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <directory_to_scan> [output_dir]"
    exit 1
fi

TARGET_DIR="$1"
OUTPUT_DIR="${2:-.}"

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: '$TARGET_DIR' is not a valid directory." >&2
    exit 1
fi

if [[ ! -d "$OUTPUT_DIR" ]]; then
    echo "Error: output directory '$OUTPUT_DIR' does not exist." >&2
    exit 1
fi

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
REPORT_FILE="$OUTPUT_DIR/world_writable_audit_${TIMESTAMP}.txt"
CSV_FILE="$OUTPUT_DIR/world_writable_audit_${TIMESTAMP}.csv"

# ---------- 1. Header ----------

{
    echo "==================================================================="
    echo " WORLD-WRITABLE FILE AUDIT REPORT"
    echo "==================================================================="
    echo " Scanned directory : $TARGET_DIR"
    echo " Scan started at   : $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Run by            : $(whoami)"
    echo " Hostname          : $(hostname)"
    echo "==================================================================="
    echo ""
} > "$REPORT_FILE"

echo "path,type,permissions,owner,group,size_bytes,last_modified" > "$CSV_FILE"

# ---------- 2. Find world-writable files and directories ----------
# -perm -0002 matches anything where the "other write" bit is set,
# regardless of what else is set (setuid, sticky, etc.)

FOUND_COUNT=0

# Use -print0/read -d to safely handle filenames with spaces/newlines
while IFS= read -r -d '' item; do
    FOUND_COUNT=$((FOUND_COUNT + 1))

    if [[ -d "$item" ]]; then
        TYPE="directory"
    elif [[ -L "$item" ]]; then
        TYPE="symlink"
    else
        TYPE="file"
    fi

    # macOS/BSD stat format
    PERMS=$(stat -f "%Sp" "$item" 2>/dev/null)
    OWNER=$(stat -f "%Su" "$item" 2>/dev/null)
    GROUPNAME=$(stat -f "%Sg" "$item" 2>/dev/null)
    SIZE=$(stat -f "%z" "$item" 2>/dev/null)
    MTIME=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$item" 2>/dev/null)

    # Flag extra-risky items: world-writable AND setuid/setgid
    RISK_FLAG=""
    if [[ "$PERMS" == *s* || "$PERMS" == *S* ]]; then
        RISK_FLAG=" [HIGH RISK: setuid/setgid + world-writable]"
    fi

    {
        echo "[$TYPE] $item$RISK_FLAG"
        echo "    Permissions : $PERMS"
        echo "    Owner:Group : $OWNER:$GROUPNAME"
        echo "    Size        : ${SIZE} bytes"
        echo "    Modified    : $MTIME"
        echo ""
    } >> "$REPORT_FILE"

    # Escape any commas/quotes in path for CSV safety
    SAFE_PATH=$(printf '%s' "$item" | sed 's/"/""/g')
    echo "\"$SAFE_PATH\",$TYPE,$PERMS,$OWNER,$GROUPNAME,$SIZE,\"$MTIME\"" >> "$CSV_FILE"

done < <(find "$TARGET_DIR" -perm -0002 \( -type f -o -type d -o -type l \) -print0 2>/dev/null)

# ---------- 3. Summary footer ----------

{
    echo "==================================================================="
    echo " SUMMARY"
    echo "==================================================================="
    echo " Total world-writable items found : $FOUND_COUNT"
    echo " Scan completed at                : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "==================================================================="
} >> "$REPORT_FILE"

# ---------- 4. Console output ----------

echo "Audit complete."
echo "  Items flagged     : $FOUND_COUNT"
echo "  Text report       : $REPORT_FILE"
echo "  CSV report        : $CSV_FILE"

if [[ $FOUND_COUNT -gt 0 ]]; then
    echo ""
    echo "WARNING: $FOUND_COUNT world-writable item(s) found. Review the report and consider running:"
    echo "  chmod o-w <path>   # to remove world-write permission"
fi
