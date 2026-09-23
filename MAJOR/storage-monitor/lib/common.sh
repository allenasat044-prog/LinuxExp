#!/usr/bin/env bash
# ============================================================
# common.sh - shared functions for the storage monitor toolkit
# ============================================================

# Resolve project root regardless of where this is sourced from
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${LIB_DIR}/.." && pwd)"
CONF_FILE="${PROJECT_ROOT}/conf/storage-monitor.conf"

if [[ -f "${CONF_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${CONF_FILE}"
else
    echo "FATAL: config file not found at ${CONF_FILE}" >&2
    exit 1
fi

mkdir -p "${DATA_DIR}" "${LOG_DIR}" "${REPORT_DIR}"

# ---------- logging ----------
log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${ts}] [${level}] ${msg}" | tee -a "${LOG_FILE}" >/dev/null
    if [[ "${level}" != "INFO" ]]; then
        echo "[${ts}] [${level}] ${msg}"
    fi
}

log_info()  { log "INFO"  "$@"; }
log_warn()  { log "WARN"  "$@"; }
log_crit()  { log "CRIT"  "$@"; }
log_error() { log "ERROR" "$@"; }

# ---------- OS detection ----------
detect_os() {
    case "$(uname -s)" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "macos" ;;
        *)       echo "unsupported" ;;
    esac
}

# ---------- alerting ----------
send_alert() {
    local severity="$1"   # WARN | CRIT
    local subject="$2"
    local body="$3"

    log_"${severity,,}" "${subject} :: ${body}"

    if [[ "${ALERT_SYSLOG_ENABLED}" == "true" ]] && command -v logger >/dev/null 2>&1; then
        logger -t storage-monitor -p "user.${severity,,}" "${subject}: ${body}"
    fi

    if [[ "${ALERT_EMAIL_ENABLED}" == "true" ]] && command -v mail >/dev/null 2>&1; then
        echo "${body}" | mail -s "[${severity}] Storage Monitor: ${subject}" "${ALERT_EMAIL_TO}"
    fi

    if [[ "${ALERT_WEBHOOK_ENABLED}" == "true" ]] && command -v curl >/dev/null 2>&1; then
        local payload
        payload=$(printf '{"text":"*[%s] Storage Monitor*\\n%s\\n%s"}' "${severity}" "${subject}" "${body}")
        curl -s -X POST -H 'Content-type: application/json' \
            --data "${payload}" "${ALERT_WEBHOOK_URL}" >/dev/null 2>&1
    fi
}

# ---------- helpers ----------
# Convert a df size like "10G" / "512M" / "1024K" to MB (integer)
to_mb() {
    local val="$1"
    numfmt --from=iec --to-unit=1M "${val}" 2>/dev/null || echo 0
}

human_bytes() {
    numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "$1"
}
