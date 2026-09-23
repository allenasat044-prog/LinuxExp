#!/usr/bin/env bash
# ============================================================
# storage-monitor.sh
# Monitors disk space usage and inode usage across mounted
# filesystems, and fires alerts when thresholds are crossed.
#
# Usage:
#   ./storage-monitor.sh [--quiet] [--json]
#
# Exit codes:
#   0 = OK, 1 = WARN threshold hit, 2 = CRIT threshold hit
# ============================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

QUIET=false
JSON_OUT=false
for arg in "$@"; do
    case "$arg" in
        --quiet) QUIET=true ;;
        --json)  JSON_OUT=true ;;
        -h|--help)
            echo "Usage: $0 [--quiet] [--json]"
            exit 0
            ;;
    esac
done

OS="$(detect_os)"
if [[ "${OS}" == "unsupported" ]]; then
    log_error "Unsupported OS: $(uname -s). This script supports Linux and macOS."
    exit 1
fi

EXIT_CODE=0
JSON_ROWS=()

log_info "Starting storage scan (OS=${OS})"

# ---------- gather filesystem list ----------
# df -P gives POSIX-portable output across Linux/macOS
if [[ -n "${MONITORED_MOUNTS}" ]]; then
    read -ra MOUNTS <<< "${MONITORED_MOUNTS}"
    DF_LINES=$(df -P "${MOUNTS[@]}" 2>/dev/null | tail -n +2)
else
    DF_LINES=$(df -P -l 2>/dev/null | tail -n +2 | grep -Ev '^(tmpfs|devtmpfs|overlay|squashfs|udev)')
fi

while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    fs=$(awk '{print $1}' <<< "$line")
    size_kb=$(awk '{print $2}' <<< "$line")
    used_kb=$(awk '{print $3}' <<< "$line")
    avail_kb=$(awk '{print $4}' <<< "$line")
    use_pct=$(awk '{gsub("%","",$5); print $5}' <<< "$line")
    mount=$(awk '{print $6}' <<< "$line")

    [[ -z "$use_pct" ]] && continue

    status="OK"
    if (( use_pct >= DISK_CRIT_THRESHOLD )); then
        status="CRIT"
        EXIT_CODE=2
        send_alert "CRIT" "Disk usage critical on ${mount}" \
            "Filesystem ${fs} mounted at ${mount} is at ${use_pct}% (threshold ${DISK_CRIT_THRESHOLD}%). Avail: $(human_bytes $((avail_kb*1024)))"
    elif (( use_pct >= DISK_WARN_THRESHOLD )); then
        status="WARN"
        [[ $EXIT_CODE -lt 1 ]] && EXIT_CODE=1
        send_alert "WARN" "Disk usage high on ${mount}" \
            "Filesystem ${fs} mounted at ${mount} is at ${use_pct}% (threshold ${DISK_WARN_THRESHOLD}%). Avail: $(human_bytes $((avail_kb*1024)))"
    else
        log_info "Disk OK: ${mount} (${fs}) at ${use_pct}%"
    fi

    # ---- inode check (Linux only; macOS df -i behaves differently/unreliably) ----
    inode_pct="n/a"
    if [[ "${OS}" == "linux" ]]; then
        inode_line=$(df -iP "${mount}" 2>/dev/null | tail -n +2)
        inode_pct=$(awk '{gsub("%","",$5); print $5}' <<< "$inode_line")
        if [[ -n "$inode_pct" && "$inode_pct" =~ ^[0-9]+$ ]]; then
            if (( inode_pct >= INODE_CRIT_THRESHOLD )); then
                status="CRIT"
                EXIT_CODE=2
                send_alert "CRIT" "Inode usage critical on ${mount}" \
                    "Filesystem ${fs} mounted at ${mount} inode usage at ${inode_pct}% (threshold ${INODE_CRIT_THRESHOLD}%)."
            elif (( inode_pct >= INODE_WARN_THRESHOLD )); then
                [[ "$status" == "OK" ]] && status="WARN"
                [[ $EXIT_CODE -lt 1 ]] && EXIT_CODE=1
                send_alert "WARN" "Inode usage high on ${mount}" \
                    "Filesystem ${fs} mounted at ${mount} inode usage at ${inode_pct}% (threshold ${INODE_WARN_THRESHOLD}%)."
            fi
        fi
    fi

    JSON_ROWS+=("{\"mount\":\"${mount}\",\"filesystem\":\"${fs}\",\"disk_used_pct\":${use_pct},\"inode_used_pct\":\"${inode_pct}\",\"status\":\"${status}\"}")

    if [[ "${QUIET}" == "false" && "${JSON_OUT}" == "false" ]]; then
        printf "%-25s %-15s disk:%3s%%  inode:%-5s  [%s]\n" "$mount" "$fs" "$use_pct" "$inode_pct" "$status"
    fi
done <<< "$DF_LINES"

if [[ "${JSON_OUT}" == "true" ]]; then
    printf '{"timestamp":"%s","results":[%s]}\n' "$(date -Iseconds)" "$(IFS=,; echo "${JSON_ROWS[*]}")"
fi

log_info "Storage scan complete. exit_code=${EXIT_CODE}"
exit "${EXIT_CODE}"
