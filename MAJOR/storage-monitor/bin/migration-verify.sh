#!/usr/bin/env bash
# ============================================================
# migration-verify.sh
# Captures a "before" snapshot of a directory (file count,
# total size, checksums), then after migration compares it
# to an "after" snapshot and produces a pass/fail report.
#
# Usage:
#   ./migration-verify.sh before <source_dir> <label>
#   ./migration-verify.sh after  <dest_dir>   <label>
# ============================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

MIGRATION_DIR="${DATA_DIR}/migrations"
mkdir -p "${MIGRATION_DIR}"

CMD="${1:-}"
TARGET_DIR="${2:-}"
LABEL="${3:-}"

if [[ -z "$CMD" || -z "$TARGET_DIR" || -z "$LABEL" ]]; then
    echo "Usage:"
    echo "  $0 before <source_dir> <label>"
    echo "  $0 after  <dest_dir>   <label>"
    exit 1
fi

if [[ ! -d "$TARGET_DIR" ]]; then
    log_error "Directory not found: $TARGET_DIR"
    exit 1
fi

snapshot_dir() {
    local dir="$1"
    local file_count total_size_kb checksum
    file_count=$(find "$dir" -type f 2>/dev/null | wc -l | tr -d ' ')
    total_size_kb=$(du -sk "$dir" 2>/dev/null | awk '{print $1}')
    # Aggregate checksum: sha256 of the sorted list of (relative_path, md5) pairs.
    # This detects added/removed/modified files without hashing huge trees twice.
    checksum=$(find "$dir" -type f -exec md5sum {} \; 2>/dev/null \
        | sed "s|$dir/||" \
        | sort \
        | sha256sum \
        | awk '{print $1}')
    echo "${file_count}|${total_size_kb}|${checksum}"
}

case "$CMD" in
    before)
        log_info "Capturing BEFORE snapshot for '${LABEL}' at ${TARGET_DIR}"
        data=$(snapshot_dir "$TARGET_DIR")
        {
            echo "label=${LABEL}"
            echo "phase=before"
            echo "path=${TARGET_DIR}"
            echo "timestamp=$(date -Iseconds)"
            echo "file_count=$(cut -d'|' -f1 <<< "$data")"
            echo "total_size_kb=$(cut -d'|' -f2 <<< "$data")"
            echo "checksum=$(cut -d'|' -f3 <<< "$data")"
        } > "${MIGRATION_DIR}/${LABEL}.before"
        log_info "Saved: ${MIGRATION_DIR}/${LABEL}.before"
        ;;

    after)
        before_file="${MIGRATION_DIR}/${LABEL}.before"
        if [[ ! -f "$before_file" ]]; then
            log_error "No 'before' snapshot found for label '${LABEL}'. Run 'before' first."
            exit 1
        fi

        log_info "Capturing AFTER snapshot for '${LABEL}' at ${TARGET_DIR}"
        data=$(snapshot_dir "$TARGET_DIR")
        after_count=$(cut -d'|' -f1 <<< "$data")
        after_size=$(cut -d'|' -f2 <<< "$data")
        after_checksum=$(cut -d'|' -f3 <<< "$data")

        # shellcheck disable=SC1090
        source <(grep -E '^(file_count|total_size_kb|checksum|path)=' "$before_file")
        before_count="$file_count"
        before_size="$total_size_kb"
        before_checksum="$checksum"
        before_path="$path"

        report_file="${REPORT_DIR}/migration-report_${LABEL}_$(date +%Y%m%d_%H%M%S).txt"

        {
            echo "=================================================="
            echo " MIGRATION VERIFICATION REPORT"
            echo "=================================================="
            echo "Label:          ${LABEL}"
            echo "Source (before): ${before_path}"
            echo "Dest   (after):  ${TARGET_DIR}"
            echo "Generated:      $(date -Iseconds)"
            echo "--------------------------------------------------"
            printf "%-20s %-15s %-15s\n" "METRIC" "BEFORE" "AFTER"
            printf "%-20s %-15s %-15s\n" "File count" "$before_count" "$after_count"
            printf "%-20s %-15s %-15s\n" "Total size" "$(human_bytes $((before_size*1024)))" "$(human_bytes $((after_size*1024)))"
            echo "--------------------------------------------------"

            status="PASS"
            if [[ "$before_count" != "$after_count" ]]; then
                echo "[FAIL] File count mismatch: ${before_count} -> ${after_count}"
                status="FAIL"
            fi
            if [[ "$before_checksum" != "$after_checksum" ]]; then
                echo "[FAIL] Content checksum mismatch - file contents differ or files missing/added"
                status="FAIL"
            fi
            if [[ "$status" == "PASS" ]]; then
                echo "[PASS] File count matches"
                echo "[PASS] Content checksum matches - migration verified byte-for-byte consistent"
            fi
            echo "--------------------------------------------------"
            echo "RESULT: ${status}"
            echo "=================================================="
        } | tee "${report_file}"

        log_info "Migration report saved: ${report_file}"

        if grep -q "RESULT: FAIL" "${report_file}"; then
            send_alert "CRIT" "Migration verification FAILED (${LABEL})" \
                "See report: ${report_file}"
            exit 2
        else
            log_info "Migration '${LABEL}' verified successfully."
            exit 0
        fi
        ;;
    *)
        echo "Usage: $0 {before|after} <dir> <label>"
        exit 1
        ;;
esac
