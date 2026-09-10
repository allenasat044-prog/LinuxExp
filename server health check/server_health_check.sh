#!/bin/bash
#
# server_health_check.sh
#
# Quick morning health-check report for a Linux server:
#   - CPU usage
#   - Memory usage
#   - Disk usage
#   - System uptime
#   - Currently logged-in users
#
# Usage:
#   ./server_health_check.sh [-o output.txt]
#
#   -o FILE   Also save the report to a text file (in addition to printing it)
#   -h        Show this help
#
# Works on most Linux distros out of the box (uses top/free/df/uptime/who,
# all standard on Debian/Ubuntu/RHEL/CentOS/Alpine-with-procps).

set -uo pipefail

OUTPUT_FILE=""

usage() {
    grep '^#' "$0" | sed -n '2,15p' | sed 's/^# \{0,1\}//'
    exit 1
}

while getopts "o:h" opt; do
    case "$opt" in
        o) OUTPUT_FILE="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Send all report output both to the screen and, if requested, to a file
report() {
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$1" | tee -a "$OUTPUT_FILE"
    else
        echo "$1"
    fi
}

[[ -n "$OUTPUT_FILE" ]] && > "$OUTPUT_FILE"   # truncate/create fresh file

HOSTNAME_VAL=$(hostname 2>/dev/null || echo "unknown")
REPORT_DATE=$(date '+%Y-%m-%d %H:%M:%S %Z')

report "========================================================"
report " SERVER HEALTH CHECK REPORT"
report " Host: $HOSTNAME_VAL"
report " Generated: $REPORT_DATE"
report "========================================================"
report ""

# ---- CPU Usage ----
report "---- CPU USAGE ----"
if command -v mpstat >/dev/null 2>&1; then
    cpu_idle=$(mpstat 1 1 2>/dev/null | awk '/Average/ {print $NF}')
    if [[ -n "$cpu_idle" ]]; then
        cpu_used=$(awk -v idle="$cpu_idle" 'BEGIN{printf "%.1f", 100 - idle}')
        report "CPU Usage: ${cpu_used}%  (Idle: ${cpu_idle}%)"
    fi
elif command -v top >/dev/null 2>&1; then
    # Portable-ish parse of top's single-shot output
    cpu_line=$(top -bn1 2>/dev/null | grep -i "Cpu(s)")
    if [[ -n "$cpu_line" ]]; then
        cpu_idle=$(echo "$cpu_line" | awk -F'[,: ]+' '{for(i=1;i<=NF;i++){if($i ~ /id/){print $(i-1)}}}')
        if [[ -n "$cpu_idle" ]]; then
            cpu_used=$(awk -v idle="$cpu_idle" 'BEGIN{printf "%.1f", 100 - idle}')
            report "CPU Usage: ${cpu_used}%  (Idle: ${cpu_idle}%)"
        else
            report "$cpu_line"
        fi
    else
        report "Unable to read CPU usage (top output unrecognized)."
    fi
else
    # Fallback: load average from uptime, normalized per core
    if [[ -f /proc/loadavg ]]; then
        load1=$(awk '{print $1}' /proc/loadavg)
        cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)
        report "Load average (1 min): $load1  across $cores core(s)"
        report "(Install 'top' or 'sysstat' for precise CPU %)"
    else
        report "No CPU usage tool available (top/mpstat/proc not found)."
    fi
fi
report ""

# ---- Memory Usage ----
report "---- MEMORY USAGE ----"
if command -v free >/dev/null 2>&1; then
    free -h | while IFS= read -r line; do report "$line"; done
    mem_line=$(free -m | awk '/^Mem:/ {print $2, $3}')
    total_mem=$(echo "$mem_line" | awk '{print $1}')
    used_mem=$(echo "$mem_line" | awk '{print $2}')
    if [[ -n "$total_mem" && "$total_mem" -gt 0 ]]; then
        mem_pct=$(awk -v u="$used_mem" -v t="$total_mem" 'BEGIN{printf "%.1f", (u/t)*100}')
        report ""
        report "Memory used: ${mem_pct}% (${used_mem}MB / ${total_mem}MB)"
    fi
else
    report "'free' command not found — cannot report memory usage."
fi
report ""

# ---- Disk Usage ----
report "---- DISK USAGE ----"
if command -v df >/dev/null 2>&1; then
    df -h --output=source,size,used,avail,pcent,target 2>/dev/null | grep -Ev "tmpfs|udev|overlay|squashfs" | while IFS= read -r line; do
        report "$line"
    done
    # Fallback for systems where --output isn't supported (e.g. BusyBox/macOS df)
    if [[ $? -ne 0 ]]; then
        df -h | while IFS= read -r line; do report "$line"; done
    fi

    # Warn on any filesystem over 85% used
    report ""
    while read -r fs_pct fs_target; do
        pct_num=${fs_pct%\%}
        if [[ "$pct_num" =~ ^[0-9]+$ && "$pct_num" -ge 85 ]]; then
            report "⚠ WARNING: $fs_target is at ${fs_pct} disk usage"
        fi
    done < <(df -h 2>/dev/null | grep -Ev "tmpfs|udev|overlay|squashfs|Filesystem" | awk '{print $5, $6}')
else
    report "'df' command not found — cannot report disk usage."
fi
report ""

# ---- Uptime ----
report "---- SYSTEM UPTIME ----"
if command -v uptime >/dev/null 2>&1; then
    report "$(uptime -p 2>/dev/null || uptime)"
else
    report "'uptime' command not found."
fi
report ""

# ---- Logged-in Users ----
report "---- LOGGED-IN USERS ----"
if command -v who >/dev/null 2>&1; then
    who_output=$(who)
    if [[ -z "$who_output" ]]; then
        report "No users currently logged in."
    else
        report "$who_output"
        user_count=$(echo "$who_output" | wc -l | xargs)
        report ""
        report "Total active sessions: $user_count"
    fi
else
    report "'who' command not found — cannot report logged-in users."
fi
report ""

report "========================================================"
report " END OF REPORT"
report "========================================================"

if [[ -n "$OUTPUT_FILE" ]]; then
    echo ""
    echo "Report saved to: $OUTPUT_FILE"
fi

exit 0
