#!/usr/bin/env bash
# ============================================================
# install.sh
# Installs storage-monitor toolkit to /opt/storage-monitor
# (or $INSTALL_DIR) and symlinks commands onto PATH.
#
# Usage: sudo ./install.sh
# ============================================================

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/storage-monitor}"
BIN_LINK_DIR="${BIN_LINK_DIR:-/usr/local/bin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OS="$(uname -s)"
if [[ "$OS" != "Linux" && "$OS" != "Darwin" ]]; then
    echo "Unsupported OS: $OS. This installer supports Linux and macOS only."
    echo "(Storage/inode semantics differ on Windows - see README for WSL guidance.)"
    exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
    echo "Please run as root/sudo: sudo ./install.sh"
    exit 1
fi

echo "Installing to ${INSTALL_DIR} ..."
mkdir -p "${INSTALL_DIR}"
cp -r "${SCRIPT_DIR}/bin" "${SCRIPT_DIR}/lib" "${SCRIPT_DIR}/conf" "${INSTALL_DIR}/"
mkdir -p "${INSTALL_DIR}/logs" "${INSTALL_DIR}/reports" "${INSTALL_DIR}/data"

# Make runtime dirs writable by whoever invoked sudo, not just root,
# so normal (non-sudo) commands can write logs/reports/snapshots later.
REAL_USER="${SUDO_USER:-$(whoami)}"
chown -R "${REAL_USER}" "${INSTALL_DIR}/logs" "${INSTALL_DIR}/reports" "${INSTALL_DIR}/data" 2>/dev/null || true

chmod +x "${INSTALL_DIR}"/bin/*.sh

# Use wrapper scripts rather than symlinks: a symlinked script resolves
# BASH_SOURCE relative to /usr/local/bin, not its real location, which
# breaks the "source ../lib/common.sh" path inside each script.
for script in storage-monitor growth-tracker generate-report migration-verify; do
    rm -f "${BIN_LINK_DIR}/${script}"
    cat > "${BIN_LINK_DIR}/${script}" <<EOF
#!/usr/bin/env bash
exec "${INSTALL_DIR}/bin/${script}.sh" "\$@"
EOF
    chmod +x "${BIN_LINK_DIR}/${script}"
    echo "  installed: ${BIN_LINK_DIR}/${script} -> ${INSTALL_DIR}/bin/${script}.sh"
done

echo ""
echo "Installed. Try:"
echo "  storage-monitor"
echo "  growth-tracker snapshot"
echo "  generate-report"
echo "  migration-verify before /path/to/source mylabel"
echo ""
echo "Edit ${INSTALL_DIR}/conf/storage-monitor.conf to set thresholds and alert channels."
echo "See README.md for cron/systemd scheduling setup."
