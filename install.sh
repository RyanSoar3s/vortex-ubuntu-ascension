#!/usr/bin/env bash
# Install the "Vortex Ubuntu Ascension" Plymouth theme (Ubuntu/Debian).
# Usage: sudo ./install.sh
set -euo pipefail

THEME="vortex-ubuntu-ascension"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="/usr/share/plymouth/themes/${THEME}"
ALTERNATIVE="/usr/share/plymouth/themes/default.plymouth"

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "Run as root: sudo $0" >&2
        exit 1
    fi
}

require_root

echo "==> Copying theme to ${DEST_DIR}"
mkdir -p "${DEST_DIR}"
cp -a "${SRC_DIR}/." "${DEST_DIR}/"
# Remove helper scripts that are not used by Plymouth.
rm -f "${DEST_DIR}/install.sh" "${DEST_DIR}/uninstall.sh"

echo "==> Registering theme with update-alternatives"
update-alternatives --install "${ALTERNATIVE}" default.plymouth \
    "${DEST_DIR}/${THEME}.plymouth" 200

echo "==> Selecting theme as default"
update-alternatives --set default.plymouth "${DEST_DIR}/${THEME}.plymouth"

echo "==> Rebuilding initramfs"
update-initramfs -u

echo
echo "Done! Theme '${THEME}' has been installed and activated."
echo "To test without rebooting:"
echo "    sudo plymouthd; sudo plymouth --show-splash; sleep 15; sudo plymouth quit"
