#!/usr/bin/env bash
# Remove the "Vortex Ubuntu Ascension" Plymouth theme and restore the previous theme.
# Usage: sudo ./uninstall.sh
set -euo pipefail

THEME="vortex-ubuntu-ascension"
DEST_DIR="/usr/share/plymouth/themes/${THEME}"
STATE_DIR="/var/lib/${THEME}"
PREVIOUS_THEME="${STATE_DIR}/previous-default.plymouth"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

echo "==> Removing update-alternatives entry"
if ! update-alternatives --remove default.plymouth "${DEST_DIR}/${THEME}.plymouth"; then
    if alternatives="$(update-alternatives --query default.plymouth 2>/dev/null)" \
        && grep -Fqx "Alternative: ${DEST_DIR}/${THEME}.plymouth" <<< "${alternatives}"; then
        echo "Error: the theme is still registered; refusing to remove its files." >&2
        exit 1
    fi
    echo "The theme was not registered; continuing with file removal."
fi

echo "==> Deleting theme files"
rm -rf "${DEST_DIR}"

echo "==> Restoring the previous Plymouth theme when available"
if alternatives="$(update-alternatives --query default.plymouth 2>/dev/null)"; then
    previous_theme=""
    if [[ -f "${PREVIOUS_THEME}" ]]; then
        IFS= read -r previous_theme < "${PREVIOUS_THEME}"
    fi

    if [[ -n "${previous_theme}" && -f "${previous_theme}" ]] \
        && grep -Fqx "Alternative: ${previous_theme}" <<< "${alternatives}"; then
        update-alternatives --set default.plymouth "${previous_theme}"
        echo "Restored previous Plymouth theme: ${previous_theme}"
    else
        echo "No registered previous theme is available; selecting automatically."
        if ! update-alternatives --auto default.plymouth; then
            echo "Warning: automatic selection failed; no default Plymouth theme may be configured." >&2
        fi
    fi
else
    echo "No Plymouth alternatives remain registered; automatic selection is unavailable."
fi

echo "==> Rebuilding initramfs"
update-initramfs -u

rm -f "${PREVIOUS_THEME}"
if [[ -d "${STATE_DIR}" ]] && ! rmdir "${STATE_DIR}" 2>/dev/null; then
    echo "Warning: could not remove state directory ${STATE_DIR}." >&2
fi

echo "Theme '${THEME}' has been removed."
