#!/usr/bin/env bash
# Remove the "Vortex Ubuntu Ascension" Plymouth theme and restore prior settings.
# Usage: sudo ./uninstall.sh
set -euo pipefail

THEME="vortex-ubuntu-ascension"
DEST_DIR="/usr/share/plymouth/themes/${THEME}"
THEME_FILE="${DEST_DIR}/${THEME}.plymouth"
STATE_DIR="/var/lib/${THEME}"
PREVIOUS_THEME="${STATE_DIR}/previous-default.plymouth"
PREVIOUS_MODE="${STATE_DIR}/previous-alternatives-mode"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

for command_name in update-alternatives update-initramfs; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "${command_name} is required to uninstall the Plymouth theme." >&2
        exit 1
    fi
done

previous_theme=""
if [[ -f "${PREVIOUS_THEME}" ]]; then
    IFS= read -r previous_theme < "${PREVIOUS_THEME}" || true
fi

previous_mode=""
if [[ -f "${PREVIOUS_MODE}" ]]; then
    IFS= read -r previous_mode < "${PREVIOUS_MODE}" || true
fi
# Compatibility with state created by earlier versions of the installer.
if [[ "${previous_mode}" != "auto" && "${previous_mode}" != "manual" ]]; then
    if [[ -n "${previous_theme}" ]]; then
        previous_mode="manual"
    else
        previous_mode="auto"
    fi
fi

echo "==> Removing update-alternatives entry"
if ! update-alternatives --remove default.plymouth "${THEME_FILE}"; then
    if alternatives="$(update-alternatives --query default.plymouth 2>/dev/null)" \
        && grep -Fqx "Alternative: ${THEME_FILE}" <<< "${alternatives}"; then
        echo "Error: the theme is still registered; refusing to remove its files." >&2
        exit 1
    fi
    echo "The theme was not registered; continuing with file removal."
fi

echo "==> Deleting theme files"
rm -rf -- "${DEST_DIR}"

echo "==> Restoring the previous Plymouth selection mode"
if alternatives="$(update-alternatives --query default.plymouth 2>/dev/null)"; then
    if [[ "${previous_mode}" == "auto" ]]; then
        update-alternatives --auto default.plymouth
        echo "Restored automatic Plymouth theme selection."
    elif [[ -n "${previous_theme}" && -f "${previous_theme}" ]] \
        && grep -Fqx "Alternative: ${previous_theme}" <<< "${alternatives}"; then
        update-alternatives --set default.plymouth "${previous_theme}"
        echo "Restored previous Plymouth theme: ${previous_theme}"
    else
        echo "The saved theme is unavailable; selecting an available theme automatically."
        update-alternatives --auto default.plymouth
    fi
else
    echo "No Plymouth alternatives remain registered; no selection can be restored."
fi

echo "==> Rebuilding initramfs"
update-initramfs -u

rm -f -- "${PREVIOUS_THEME}" "${PREVIOUS_MODE}"
if [[ -d "${STATE_DIR}" ]] && ! rmdir -- "${STATE_DIR}" 2>/dev/null; then
    echo "Warning: could not remove state directory ${STATE_DIR}." >&2
fi

echo "Theme '${THEME}' has been removed."
