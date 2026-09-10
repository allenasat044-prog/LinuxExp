#!/bin/bash
#
# audit_ownership.sh
# Scans a project directory for files/folders NOT owned by the designated
# project administrator, and generates a timestamped audit report.
# Written for macOS (BSD find/stat).
#
# Usage:
#   ./audit_ownership.sh <project_directory> <admin_username> [output_dir]
#
# Example:
#   ./audit_ownership.sh ~/Projects/WebApp shashank ~/Desktop
#
set -uo pipefail

# ---------- 0. Input validation ----------

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <project_directory> <admin_username> [output_dir]"
    exit 1
fi

PROJECT_DIR="$1"
ADMIN_USER="$2"
OUTPUT_DIR="${3:-.}"

if [[ ! -d "$PROJECT_DIR" ]]; then
    echo "Error: '$PROJECT_DIR' is not a valid directory." >&2
    exit 1
fi

if [[ ! -d "$OUTPUT_DIR" ]]; then
    echo "Error: output directory '$OUTPUT_DIR' does not exist." >&2
    exit 1
fi

# Verify the admin username actually exists on this system
if ! id "$ADMIN_USER" >/dev/null 2>&1; then
    echo "Error: user '$ADMIN_USER' does not exist on this system." >&2
    exit 1
fi

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
REPORT_FILE="$OUTPUT_DIR/ownership_audit_${TIMESTAMP}.txt"
CSV_FILE="$OUTPUT_DIR/ownership_audit_${TIMESTAMP}.csv"

# ---------- 1. Header ----------

{
    echo "==================================================================="
    echo " FILE OWNERSHIP AUDIT REPORT"
    echo "==================================================================="
    echo " Scanned directory      : $PROJECT_DIR"
    echo " Designated admin       : $ADMIN_USER"
    echo " Scan started at        : $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Run by                 : $(whoami)"
    echo " Hostname               : $(hostname)"
    echo "==================================================================="
    echo ""
} > "$REPORT_FILE"

echo "path,type,owner,group,permissions,size_bytes,last_modified" > "$CSV_FILE"

# ---------- 2. Find files/dirs NOT owned by the admin ----------
# ! -user excludes anything owned by the admin, leaving only mismatches

FOUND_COUNT=0
declare -A OWNER_COUNTS

while IFS= read -r -d '' item; do
    FOUND_COUNT=$((FOUND_COUNT + 1))

    if [[ -d "$item" ]]; then
        TYPE="directory"
    elif [[ -L "$item" ]]; then
        TYPE="symlink"
    else
        TYPE="file"
    fi

    OWNER=$(stat -f "%Su" "$item" 2>/dev/null)
    GROUPNAME=$(stat -f "%Sg" "$item" 2>/dev/null)
    PERMS=$(stat -f "%Sp" "$item" 2>/dev/null)
    SIZE=$(stat -f "%z" "$item" 2>/dev/null)
    MTIME=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$item" 2>/dev/null)

    # Tally how many mismatched files belong to each unexpected owner
    OWNER_COUNTS["$OWNER"]=$(( ${OWNER_COUNTS["$OWNER"]:-0} + 1 ))

    {
        echo "[$TYPE] $item"
        echo "    Owner       : $OWNER  (expected: $ADMIN_USER)"
        echo "    Group       : $GROUPNAME"
        echo "    Permissions : $PERMS"
        echo "    Size        : ${SIZE} bytes"
        echo "    Modified    : $MTIME"
        echo ""
    } >> "$REPORT_FILE"

    SAFE_PATH=$(printf '%s' "$item" | sed 's/"/""/g')
    echo "\"$SAFE_PATH\",$TYPE,$OWNER,$GROUPNAME,$PERMS,$SIZE,\"$MTIME\"" >> "$CSV_FILE"

done < <(find "$PROJECT_DIR" \( -type f -o -type d -o -type l \) ! -user "$ADMIN_USER" -print0 2>/dev/null)

# ---------- 3. Summary footer ----------

{
    echo "==================================================================="
    echo " SUMMARY"
    echo "==================================================================="
    echo " Total mismatched items found : $FOUND_COUNT"
    if [[ $FOUND_COUNT -gt 0 ]]; then
        echo ""
        echo " Breakdown by unexpected owner:"
        for owner in "${!OWNER_COUNTS[@]}"; do
            echo "   - $owner : ${OWNER_COUNTS[$owner]} item(s)"
        done
    fi
    echo ""
    echo " Scan completed at            : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "==================================================================="
} >> "$REPORT_FILE"

# ---------- 4. Console output ----------

echo "Ownership audit complete."
echo "  Expected admin     : $ADMIN_USER"
echo "  Mismatched items   : $FOUND_COUNT"
echo "  Text report        : $REPORT_FILE"
echo "  CSV report         : $CSV_FILE"

if [[ $FOUND_COUNT -gt 0 ]]; then
    echo ""
    echo "WARNING: $FOUND_COUNT item(s) not owned by '$ADMIN_USER'. To fix ownership, review the report then run:"
    echo "  sudo chown $ADMIN_USER <path>"
fi
