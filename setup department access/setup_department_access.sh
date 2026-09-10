#!/bin/bash
#
# setup_department_access.sh
# Create a department group and a shared directory accessible ONLY to
# members of that group. Written for macOS (uses dscl / dseditgroup / ACLs).
#
# Usage:
#   sudo ./setup_department_access.sh <group_name> <shared_dir_path> [user1 user2 ...]
#
# Example:
#   sudo ./setup_department_access.sh finance /Shared/Finance alice bob
#
set -euo pipefail

# ---------- 0. Pre-flight checks ----------

if [[ $EUID -ne 0 ]]; then
    echo "Error: this script must be run with sudo/root privileges." >&2
    exit 1
fi

if [[ $# -lt 2 ]]; then
    echo "Usage: sudo $0 <group_name> <shared_dir_path> [user1 user2 ...]"
    exit 1
fi

GROUP_NAME="$1"
SHARE_DIR="$2"
shift 2
MEMBERS=("$@")

LOG_FILE="/var/log/dept_access_setup.log"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') | $*" | tee -a "$LOG_FILE"; }

log "=== Starting department access setup for group '$GROUP_NAME' ==="

# ---------- 1. Create the group (if it doesn't already exist) ----------

if dscl . -read /Groups/"$GROUP_NAME" >/dev/null 2>&1; then
    log "Group '$GROUP_NAME' already exists. Skipping creation."
else
    # Find a free GID starting at 600 (avoid system-reserved range < 500)
    GID=600
    while dscl . -search /Groups PrimaryGroupID "$GID" | grep -q "$GID"; do
        GID=$((GID + 1))
    done

    dscl . -create /Groups/"$GROUP_NAME"
    dscl . -create /Groups/"$GROUP_NAME" PrimaryGroupID "$GID"
    dscl . -create /Groups/"$GROUP_NAME" RealName "$GROUP_NAME Department"
    log "Created group '$GROUP_NAME' with GID $GID"
fi

# ---------- 2. Add members to the group ----------

if [[ ${#MEMBERS[@]} -gt 0 ]]; then
    for user in "${MEMBERS[@]}"; do
        if ! id "$user" >/dev/null 2>&1; then
            log "WARNING: user '$user' does not exist locally. Skipping."
            continue
        fi
        if dseditgroup -o checkmember -m "$user" "$GROUP_NAME" >/dev/null 2>&1; then
            log "User '$user' is already a member of '$GROUP_NAME'."
        else
            dseditgroup -o edit -a "$user" -t user "$GROUP_NAME"
            log "Added user '$user' to group '$GROUP_NAME'."
        fi
    done
else
    log "No initial members specified. Add later with:"
    log "  sudo dseditgroup -o edit -a <username> -t user $GROUP_NAME"
fi

# ---------- 3. Create the shared directory ----------

if [[ -d "$SHARE_DIR" ]]; then
    log "Directory '$SHARE_DIR' already exists."
else
    mkdir -p "$SHARE_DIR"
    log "Created directory '$SHARE_DIR'."
fi

# ---------- 4. Lock ownership and permissions ----------

# Owner: root, Group: department group
chown root:"$GROUP_NAME" "$SHARE_DIR"

# Base POSIX permissions:
#   rwx for owner, rwx for group, nothing for others
#   Setgid bit (2) so new files/folders inherit the group
chmod 2770 "$SHARE_DIR"

log "Set ownership to root:$GROUP_NAME and permissions to 2770 (rwxrws---)."

# ---------- 5. Apply an explicit ACL as a hard backstop ----------
# This ensures ONLY the department group (and root) can read/write/traverse,
# regardless of umask or future permission drift.

# Clear any existing ACLs first
chmod -N "$SHARE_DIR" 2>/dev/null || true

# Deny access to "everyone" then explicitly allow the group
chmod +a "group:$GROUP_NAME allow list,add_file,search,delete,add_subdirectory,delete_child,read_attr,write_attr,read_extattr,write_extattr,read_security,change_owner,file_inherit,directory_inherit" "$SHARE_DIR"
chmod +a "everyone deny list,add_file,search,delete,add_subdirectory,delete_child,read_attr,write_attr,read_extattr,write_extattr,read_security,change_owner" "$SHARE_DIR"

log "Applied ACL: '$GROUP_NAME' allowed, 'everyone' explicitly denied."

# ---------- 6. Verification ----------

log "--- Verification ---"
log "Group info:"
dscl . -read /Groups/"$GROUP_NAME" GroupMembership PrimaryGroupID 2>&1 | tee -a "$LOG_FILE"

log "Directory permissions:"
ls -lde "$SHARE_DIR" | tee -a "$LOG_FILE"

log "=== Setup complete for '$GROUP_NAME' -> '$SHARE_DIR' ==="
echo ""
echo "Done. Only members of the '$GROUP_NAME' group can access: $SHARE_DIR"
echo "Log written to: $LOG_FILE"
