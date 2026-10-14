#!/usr/bin/env bash
# Remove the "Vortex Ubuntu Ascension" Plymouth theme and restore the previous theme.
# Usage: sudo ./uninstall.sh
set -euo pipefail

THEME="vortex-ubuntu-ascension"
DEST_DIR="/usr/share/plymouth/themes/${THEME}"
ALTERNATIVE="/usr/share/plymouth/themes/default.plymouth"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

echo "==> Removing update-alternatives entry"
update-alternatives --remove default.plymouth "${DEST_DIR}/${THEME}.plymouth" || true

echo "==> Automatically selecting another available theme"
update-alternatives --auto default.plymouth >/dev/null 2>&1 || true

echo "==> Deleting theme files"
rm -rf "${DEST_DIR}"

echo "==> Rebuilding initramfs"
update-initramfs -u

echo "Theme '${THEME}' has been removed."
