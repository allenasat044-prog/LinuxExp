#!/bin/bash
#
# create_employees.sh
#
# Bulk-creates Linux user accounts from a CSV employee list and assigns
# each user to their department's group (creating the group if needed).
#
# Usage:
#   sudo ./create_employees.sh employees.csv
#
# CSV format (no header row), one employee per line:
#   username,Full Name,department
#
# Example:
#   jsmith,John Smith,engineering
#   awong,Alice Wong,marketing
#   rkhan,Raj Khan,engineering
#
# Behavior:
#   - Creates the department group if it doesn't already exist
#   - Creates the user with a home directory, bash shell, and the
#     department as their primary group
#   - Sets a random temporary password and forces a change at first login
#   - Skips (with a warning) any user or line that's already handled
#   - Logs every action to a timestamped log file
#
# Exit codes: 0 = success (or partial success with warnings logged)
#             1 = fatal error (bad args, not root, missing file)

set -uo pipefail

# ---- Config -----------------------------------------------------------
LOG_FILE="./employee_setup_$(date +%Y%m%d_%H%M%S).log"
DEFAULT_SHELL="/bin/bash"

# ---- Helpers ------------------------------------------------------------
log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] [$level] $msg" | tee -a "$LOG_FILE"
}

die() {
    log "ERROR" "$*"
    exit 1
}

usage() {
    echo "Usage: sudo $0 <employee_list.csv>"
    exit 1
}

# ---- Pre-flight checks --------------------------------------------------
[[ $# -eq 1 ]] || usage

INPUT_FILE="$1"

if [[ $EUID -ne 0 ]]; then
    die "This script must be run as root (use sudo)."
fi

if [[ ! -f "$INPUT_FILE" ]]; then
    die "Input file not found: $INPUT_FILE"
fi

log "INFO" "Starting employee account setup from '$INPUT_FILE'"

created_count=0
skipped_count=0
error_count=0

# ---- Main loop ------------------------------------------------------------
# Read CSV line by line; IFS=',' splits fields; -r avoids backslash mangling
while IFS=',' read -r username fullname department || [[ -n "$username" ]]; do

    # Skip blank lines and comment lines starting with #
    [[ -z "$username" || "$username" =~ ^[[:space:]]*# ]] && continue

    # Trim leading/trailing whitespace from each field
    username=$(echo "$username" | xargs)
    fullname=$(echo "$fullname" | xargs)
    department=$(echo "$department" | xargs)

    if [[ -z "$username" || -z "$fullname" || -z "$department" ]]; then
        log "WARN" "Skipping malformed line: '$username,$fullname,$department'"
        ((skipped_count++))
        continue
    fi

    # Validate username format (POSIX-ish: lowercase, digits, -, _, max 32 chars)
    if ! [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        log "WARN" "Invalid username '$username' — skipping"
        ((skipped_count++))
        continue
    fi

    # --- Ensure department group exists ---
    if ! getent group "$department" >/dev/null 2>&1; then
        if groupadd "$department" 2>>"$LOG_FILE"; then
            log "INFO" "Created group '$department'"
        else
            log "ERROR" "Failed to create group '$department' for user '$username'"
            ((error_count++))
            continue
        fi
    fi

    # --- Skip if user already exists ---
    if id "$username" &>/dev/null; then
        log "WARN" "User '$username' already exists — skipping creation"
        ((skipped_count++))
        continue
    fi

    # --- Create the user ---
    if useradd -m -g "$department" -c "$fullname" -s "$DEFAULT_SHELL" "$username" 2>>"$LOG_FILE"; then
        log "INFO" "Created user '$username' ($fullname) in group '$department'"
    else
        log "ERROR" "Failed to create user '$username'"
        ((error_count++))
        continue
    fi

    # --- Set a random temporary password and force change at first login ---
    temp_password=$(tr -dc 'A-Za-z0-9!@#$%' </dev/urandom | head -c 12)
    if echo "${username}:${temp_password}" | chpasswd 2>>"$LOG_FILE"; then
        chage -d 0 "$username"   # force password change on first login
        log "INFO" "Temporary password set for '$username': $temp_password"
    else
        log "ERROR" "Failed to set password for '$username'"
        ((error_count++))
        continue
    fi

    ((created_count++))

done < "$INPUT_FILE"

# ---- Summary --------------------------------------------------------------
log "INFO" "Setup complete. Created: $created_count | Skipped: $skipped_count | Errors: $error_count"
log "INFO" "Full log written to: $LOG_FILE"
log "INFO" "IMPORTANT: temporary passwords are recorded in the log above — distribute securely and delete/secure the log file afterward."

[[ $error_count -eq 0 ]] && exit 0 || exit 1
