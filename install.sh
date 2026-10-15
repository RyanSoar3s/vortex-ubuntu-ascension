#!/usr/bin/env bash
# Install the "Vortex Ubuntu Ascension" Plymouth theme (Ubuntu/Debian).
# Usage: sudo ./install.sh
set -euo pipefail

THEME="vortex-ubuntu-ascension"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="/usr/share/plymouth/themes/${THEME}"
THEME_FILE="${DEST_DIR}/${THEME}.plymouth"
ALTERNATIVE="/usr/share/plymouth/themes/default.plymouth"
STATE_DIR="/var/lib/${THEME}"
PREVIOUS_THEME="${STATE_DIR}/previous-default.plymouth"
PREVIOUS_MODE="${STATE_DIR}/previous-alternatives-mode"

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "Run as root: sudo $0" >&2
        exit 1
    fi
}

require_root

for command_name in update-alternatives update-initramfs; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "${command_name} is required to install the Plymouth theme." >&2
        exit 1
    fi
done

if [[ ! -f "${SRC_DIR}/${THEME}.plymouth" || ! -f "${SRC_DIR}/${THEME}.script" ]]; then
    echo "The theme definition or script is missing from ${SRC_DIR}." >&2
    exit 1
fi

INITIAL_QUERY=""
if INITIAL_QUERY="$(update-alternatives --query default.plymouth 2>/dev/null)"; then
    :
else
    INITIAL_QUERY=""
fi
INITIAL_MODE="$(awk '$1 == "Status:" { print $2; exit }' <<< "${INITIAL_QUERY}")"
INITIAL_VALUE="$(awk '$1 == "Value:" { sub(/^Value: /, ""); print; exit }' <<< "${INITIAL_QUERY}")"
INITIAL_REGISTERED=0
INITIAL_PRIORITY=""
if grep -Fqx "Alternative: ${THEME_FILE}" <<< "${INITIAL_QUERY}"; then
    INITIAL_REGISTERED=1
    INITIAL_PRIORITY="$(awk -v target="${THEME_FILE}" '
        $1 == "Alternative:" { alternative = $2; next }
        $1 == "Priority:" && alternative == target { print $2; exit }
    ' <<< "${INITIAL_QUERY}")"
fi

BACKUP_DIR=""
DEST_BACKED_UP=0
PREVIOUS_THEME_CREATED=0
PREVIOUS_MODE_CREATED=0
INITRAMFS_ATTEMPTED=0
INSTALL_COMMITTED=0

on_exit() {
    exit_status=$?
    trap - EXIT

    if [[ "${exit_status}" -eq 0 && "${INSTALL_COMMITTED}" -eq 1 ]]; then
        if [[ -n "${BACKUP_DIR}" ]] && ! rm -rf -- "${BACKUP_DIR}"; then
            echo "Warning: could not remove temporary backup ${BACKUP_DIR}." >&2
        fi
        exit 0
    fi

    echo "Installation failed; attempting to restore the previous configuration." >&2
    rollback_failed=0

    if [[ "${DEST_BACKED_UP}" -eq 1 ]]; then
        if rm -rf -- "${DEST_DIR}" && mv -- "${BACKUP_DIR}/theme" "${DEST_DIR}"; then
            :
        else
            echo "Rollback error: could not restore ${DEST_DIR}." >&2
            rollback_failed=1
        fi
    elif [[ "${DEST_CREATED}" -eq 1 ]]; then
        if ! rm -rf -- "${DEST_DIR}"; then
            echo "Rollback error: could not remove ${DEST_DIR}." >&2
            rollback_failed=1
        fi
    fi

    if [[ "${ALTERNATIVES_CHANGED}" -eq 1 ]]; then
        if [[ "${INITIAL_REGISTERED}" -eq 1 ]]; then
            if [[ -z "${INITIAL_PRIORITY}" ]] \
                || ! update-alternatives --install "${ALTERNATIVE}" default.plymouth \
                    "${THEME_FILE}" "${INITIAL_PRIORITY}"; then
                echo "Rollback error: could not restore the original alternative registration." >&2
                rollback_failed=1
            fi
        elif ! update-alternatives --remove default.plymouth "${THEME_FILE}"; then
            current_query="$(update-alternatives --query default.plymouth 2>/dev/null || true)"
            if grep -Fqx "Alternative: ${THEME_FILE}" <<< "${current_query}"; then
                echo "Rollback error: could not unregister the Vortex alternative." >&2
                rollback_failed=1
            fi
        fi

        current_query="$(update-alternatives --query default.plymouth 2>/dev/null || true)"
        if [[ -n "${current_query}" ]]; then
            if [[ "${INITIAL_MODE}" == "auto" ]]; then
                if ! update-alternatives --auto default.plymouth; then
                    echo "Rollback error: could not restore automatic alternative selection." >&2
                    rollback_failed=1
                fi
            elif [[ "${INITIAL_MODE}" == "manual" ]] \
                && [[ -n "${INITIAL_VALUE}" ]] \
                && [[ -f "${INITIAL_VALUE}" ]] \
                && grep -Fqx "Alternative: ${INITIAL_VALUE}" <<< "${current_query}"; then
                if ! update-alternatives --set default.plymouth "${INITIAL_VALUE}"; then
                    echo "Rollback error: could not restore the previous Plymouth selection." >&2
                    rollback_failed=1
                fi
            elif ! update-alternatives --auto default.plymouth; then
                echo "Rollback error: could not select a valid Plymouth alternative." >&2
                rollback_failed=1
            fi
        fi
    fi

    if [[ "${INITRAMFS_ATTEMPTED}" -eq 1 ]] && ! update-initramfs -u; then
        echo "Rollback error: initramfs could not be rebuilt after restoration." >&2
        rollback_failed=1
    fi

    if [[ "${rollback_failed}" -eq 0 ]]; then
        rm -f -- "${PREVIOUS_THEME}.tmp" "${PREVIOUS_MODE}.tmp"
        if [[ "${PREVIOUS_THEME_CREATED}" -eq 1 ]]; then
            rm -f -- "${PREVIOUS_THEME}"
        fi
        if [[ "${PREVIOUS_MODE_CREATED}" -eq 1 ]]; then
            rm -f -- "${PREVIOUS_MODE}"
        fi
        if [[ -n "${BACKUP_DIR}" ]]; then
            rm -rf -- "${BACKUP_DIR}"
        fi
        if [[ -d "${STATE_DIR}" ]]; then
            rmdir -- "${STATE_DIR}" 2>/dev/null || true
        fi
    else
        echo "Rollback was incomplete; saved state and backup (if any) were retained for recovery." >&2
    fi
    exit "${exit_status:-1}"
}

DEST_CREATED=0
ALTERNATIVES_CHANGED=0
trap on_exit EXIT

mkdir -p "${STATE_DIR}"

# Preserve state from an earlier install. For older state files, retain the
# previous uninstaller's manual-selection behavior when a theme was saved.
if [[ ! -f "${PREVIOUS_THEME}" ]]; then
    if [[ -n "${INITIAL_VALUE}" && "${INITIAL_VALUE}" != "${THEME_FILE}" \
        && -f "${INITIAL_VALUE}" ]]; then
        printf '%s\n' "${INITIAL_VALUE}" > "${PREVIOUS_THEME}.tmp"
        mv -- "${PREVIOUS_THEME}.tmp" "${PREVIOUS_THEME}"
        PREVIOUS_THEME_CREATED=1
        echo "==> Saved previous Plymouth theme: ${INITIAL_VALUE}"
    else
        printf '\n' > "${PREVIOUS_THEME}.tmp"
        mv -- "${PREVIOUS_THEME}.tmp" "${PREVIOUS_THEME}"
        PREVIOUS_THEME_CREATED=1
        echo "==> No previous Plymouth theme is available; a valid alternative will be selected on removal"
    fi
fi

if [[ ! -f "${PREVIOUS_MODE}" ]]; then
    if [[ -f "${PREVIOUS_THEME}" ]] && [[ -s "${PREVIOUS_THEME}" ]]; then
        saved_mode="manual"
    elif [[ "${INITIAL_VALUE}" == "${THEME_FILE}" ]]; then
        saved_mode="auto"
    elif [[ "${INITIAL_MODE}" == "manual" || "${INITIAL_MODE}" == "auto" ]]; then
        saved_mode="${INITIAL_MODE}"
    else
        saved_mode="auto"
    fi
    printf '%s\n' "${saved_mode}" > "${PREVIOUS_MODE}.tmp"
    mv -- "${PREVIOUS_MODE}.tmp" "${PREVIOUS_MODE}"
    PREVIOUS_MODE_CREATED=1
    echo "==> Saved update-alternatives mode: ${saved_mode}"
fi

if [[ -e "${DEST_DIR}" ]]; then
    BACKUP_DIR="$(mktemp -d "${STATE_DIR}/install-backup.XXXXXX")"
    cp -a -- "${DEST_DIR}" "${BACKUP_DIR}/theme"
    DEST_BACKED_UP=1
else
    DEST_CREATED=1
fi

echo "==> Copying theme to ${DEST_DIR}"
mkdir -p "${DEST_DIR}"
cp -a "${SRC_DIR}/." "${DEST_DIR}/"
# Remove helper scripts that are not used by Plymouth.
rm -f "${DEST_DIR}/install.sh" "${DEST_DIR}/uninstall.sh"

echo "==> Registering theme with update-alternatives"
ALTERNATIVES_CHANGED=1
update-alternatives --install "${ALTERNATIVE}" default.plymouth \
    "${THEME_FILE}" 200

echo "==> Selecting theme as default"
update-alternatives --set default.plymouth "${THEME_FILE}"

echo "==> Rebuilding initramfs"
INITRAMFS_ATTEMPTED=1
update-initramfs -u

INSTALL_COMMITTED=1
echo
echo "Done! Theme '${THEME}' has been installed and activated."
echo "To test without rebooting:"
echo "    sudo plymouthd; sudo plymouth --show-splash; sleep 15; sudo plymouth quit"
