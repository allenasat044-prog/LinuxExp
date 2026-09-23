#!/usr/bin/env bash
# ============================================================
# generate-report.sh
# Produces a single self-contained HTML report of current
# disk/inode status and recent growth trends. No server or
# login required - just open the file in a browser.
#
# Usage: ./generate-report.sh
# ============================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

TS="$(date '+%Y-%m-%d_%H%M%S')"
OUT_FILE="${REPORT_DIR}/storage-report_${TS}.html"
JSON_DATA="$("${SCRIPT_DIR}/storage-monitor.sh" --quiet --json)"

# Build table rows from the JSON (lightweight parse, no jq dependency required)
ROWS_HTML=""
STATUS_COUNT_OK=0
STATUS_COUNT_WARN=0
STATUS_COUNT_CRIT=0

# crude JSON object splitter (fine for our flat, controlled schema)
IFS=$'\n'
for obj in $(grep -oE '\{[^}]*\}' <<< "${JSON_DATA}"); do
    mount=$(grep -oE '"mount":"[^"]*"' <<< "$obj" | cut -d'"' -f4)
    fs=$(grep -oE '"filesystem":"[^"]*"' <<< "$obj" | cut -d'"' -f4)
    disk=$(grep -oE '"disk_used_pct":[0-9]+' <<< "$obj" | cut -d':' -f2)
    inode=$(grep -oE '"inode_used_pct":"[^"]*"' <<< "$obj" | cut -d'"' -f4)
    status=$(grep -oE '"status":"[^"]*"' <<< "$obj" | cut -d'"' -f4)

    case "$status" in
        OK)   badge_class="ok"; ((STATUS_COUNT_OK++)) ;;
        WARN) badge_class="warn"; ((STATUS_COUNT_WARN++)) ;;
        CRIT) badge_class="crit"; ((STATUS_COUNT_CRIT++)) ;;
        *)    badge_class="ok" ;;
    esac

    ROWS_HTML+="<tr><td>${mount}</td><td>${fs}</td><td>${disk}%</td><td>${inode}</td><td><span class=\"badge ${badge_class}\">${status}</span></td></tr>"
done
unset IFS

# Growth trend rows (last 15 entries)
GROWTH_ROWS_HTML=""
if [[ -f "${SNAPSHOT_FILE}" ]]; then
    while IFS=, read -r ts dir size; do
        [[ "$ts" == "timestamp" ]] && continue
        human=$(human_bytes $((size*1024)))
        GROWTH_ROWS_HTML+="<tr><td>${ts}</td><td>${dir}</td><td>${human}</td></tr>"
    done < <(tail -n 15 "${SNAPSHOT_FILE}")
fi

cat > "${OUT_FILE}" <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Storage Monitoring Report - ${TS}</title>
<style>
  :root { color-scheme: light dark; }
  body { font-family: -apple-system, Segoe UI, Roboto, sans-serif; max-width: 960px; margin: 40px auto; padding: 0 20px; background:#0f1115; color:#e6e6e6; }
  h1 { font-size: 1.6rem; margin-bottom: 4px; }
  .meta { color: #9aa0a6; margin-bottom: 24px; font-size: .9rem; }
  .summary { display:flex; gap:16px; margin-bottom: 28px; flex-wrap: wrap; }
  .card { background:#1b1e26; border-radius:10px; padding:16px 20px; min-width:120px; text-align:center; }
  .card .num { font-size:1.8rem; font-weight:700; }
  .card.ok .num { color:#4ade80; }
  .card.warn .num { color:#facc15; }
  .card.crit .num { color:#f87171; }
  table { width:100%; border-collapse: collapse; margin-bottom: 32px; }
  th, td { text-align:left; padding:10px 12px; border-bottom:1px solid #2a2d36; font-size:.9rem; }
  th { color:#9aa0a6; font-weight:600; text-transform:uppercase; font-size:.75rem; letter-spacing:.04em; }
  .badge { padding:3px 10px; border-radius:20px; font-size:.75rem; font-weight:700; }
  .badge.ok   { background:#14532d; color:#4ade80; }
  .badge.warn { background:#713f12; color:#facc15; }
  .badge.crit { background:#7f1d1d; color:#f87171; }
  h2 { font-size:1.1rem; margin-top: 36px; border-left:4px solid #4f9dff; padding-left:10px; }
</style>
</head>
<body>
  <h1>Storage Monitoring Report</h1>
  <div class="meta">Generated ${TS} on host $(hostname) ($(detect_os))</div>

  <div class="summary">
    <div class="card ok"><div class="num">${STATUS_COUNT_OK}</div>OK</div>
    <div class="card warn"><div class="num">${STATUS_COUNT_WARN}</div>Warning</div>
    <div class="card crit"><div class="num">${STATUS_COUNT_CRIT}</div>Critical</div>
  </div>

  <h2>Filesystem Usage</h2>
  <table>
    <thead><tr><th>Mount</th><th>Filesystem</th><th>Disk Used</th><th>Inode Used</th><th>Status</th></tr></thead>
    <tbody>${ROWS_HTML:-"<tr><td colspan=5>No data</td></tr>"}</tbody>
  </table>

  <h2>Recent Growth Snapshots</h2>
  <table>
    <thead><tr><th>Timestamp</th><th>Directory</th><th>Size</th></tr></thead>
    <tbody>${GROWTH_ROWS_HTML:-"<tr><td colspan=3>No snapshot history yet - run growth-tracker.sh snapshot</td></tr>"}</tbody>
  </table>
</body>
</html>
HTML

log_info "Report generated: ${OUT_FILE}"
echo "${OUT_FILE}"
