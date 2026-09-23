#!/usr/bin/env bash
# ============================================================
# growth-tracker.sh
# Takes a size snapshot of configured directories, appends it
# to a CSV history, and alerts if growth since the last
# snapshot exceeds GROWTH_ALERT_MB.
#
# Usage:
#   ./growth-tracker.sh snapshot     # take a new snapshot (run via cron)
#   ./growth-tracker.sh trend <dir>  # show growth trend for a directory
# ============================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

CMD="${1:-snapshot}"

init_snapshot_file() {
    if [[ ! -f "${SNAPSHOT_FILE}" ]]; then
        echo "timestamp,directory,size_kb" > "${SNAPSHOT_FILE}"
    fi
}

take_snapshot() {
    init_snapshot_file
    local ts
    ts="$(date -Iseconds)"

    for dir in "${MONITORED_DIRS[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_warn "Monitored directory does not exist, skipping: $dir"
            continue
        fi
        local size_kb
        size_kb=$(du -sk "$dir" 2>/dev/null | awk '{print $1}')
        [[ -z "$size_kb" ]] && continue

        echo "${ts},${dir},${size_kb}" >> "${SNAPSHOT_FILE}"
        log_info "Snapshot: ${dir} = $(human_bytes $((size_kb*1024)))"

        # find previous snapshot for this dir to compute growth
        local prev_kb
        prev_kb=$(grep ",${dir}," "${SNAPSHOT_FILE}" | tail -n 2 | head -n 1 | cut -d',' -f3)

        if [[ -n "$prev_kb" && "$prev_kb" =~ ^[0-9]+$ ]]; then
            local delta_kb=$(( size_kb - prev_kb ))
            local delta_mb=$(( delta_kb / 1024 ))
            if (( delta_mb >= GROWTH_ALERT_MB )); then
                send_alert "WARN" "Rapid growth detected in ${dir}" \
                    "Grew by $(human_bytes $((delta_kb*1024))) since last snapshot (threshold ${GROWTH_ALERT_MB}MB). Current size: $(human_bytes $((size_kb*1024)))"
            fi
        fi
    done

    prune_old_snapshots
}

prune_old_snapshots() {
    [[ ! -f "${SNAPSHOT_FILE}" ]] && return
    local cutoff
    cutoff=$(date -d "-${SNAPSHOT_RETENTION_DAYS} days" +%s 2>/dev/null || date -v-"${SNAPSHOT_RETENTION_DAYS}"d +%s)
    local tmp
    tmp=$(mktemp)
    head -n 1 "${SNAPSHOT_FILE}" > "$tmp"
    tail -n +2 "${SNAPSHOT_FILE}" | while IFS=, read -r ts dir size; do
        local row_epoch
        row_epoch=$(date -d "$ts" +%s 2>/dev/null || date -jf "%Y-%m-%dT%H:%M:%S" "${ts%%+*}" +%s 2>/dev/null)
        [[ -z "$row_epoch" ]] && continue
        if (( row_epoch >= cutoff )); then
            echo "${ts},${dir},${size}"
        fi
    done >> "$tmp"
    mv "$tmp" "${SNAPSHOT_FILE}"
}

show_trend() {
    local dir="$1"
    [[ ! -f "${SNAPSHOT_FILE}" ]] && { echo "No snapshot data yet."; exit 1; }
    echo "Growth trend for: ${dir}"
    printf "%-25s %12s\n" "TIMESTAMP" "SIZE"
    grep ",${dir}," "${SNAPSHOT_FILE}" | while IFS=, read -r ts d size; do
        printf "%-25s %12s\n" "$ts" "$(human_bytes $((size*1024)))"
    done
}

case "$CMD" in
    snapshot) take_snapshot ;;
    trend)
        [[ -z "${2:-}" ]] && { echo "Usage: $0 trend <directory>"; exit 1; }
        show_trend "$2"
        ;;
    *)
        echo "Usage: $0 {snapshot|trend <directory>}"
        exit 1
        ;;
esac
