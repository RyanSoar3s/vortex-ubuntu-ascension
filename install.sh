#!/usr/bin/env bash
# Install the "Vortex Ubuntu Ascension" Plymouth theme (Ubuntu/Debian).
# Usage: sudo ./install.sh
set -Eeuo pipefail
umask 077

THEME="vortex-ubuntu-ascension"
SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
THEME_PARENT="/usr/share/plymouth/themes"
DEST_DIR="${THEME_PARENT}/${THEME}"
THEME_FILE="${DEST_DIR}/${THEME}.plymouth"
ALTERNATIVE="/usr/share/plymouth/themes/default.plymouth"
STATE_DIR="/var/lib/${THEME}"
PREVIOUS_THEME="${STATE_DIR}/previous-default.plymouth"
PREVIOUS_MODE="${STATE_DIR}/previous-alternatives-mode"

fail() {
    echo "Error: $*" >&2
    exit 1
}

query_alternatives() {
    local query_output=""
    if query_output="$(LC_ALL=C update-alternatives --query default.plymouth 2>&1)"; then
        printf '%s\n' "${query_output}"
        return 0
    fi
    if [[ "${query_output,,}" == *"no alternatives for default.plymouth"* ]]; then
        return 1
    fi
    echo "Could not query Plymouth alternatives: ${query_output}" >&2
    return 2
}

if [[ "${EUID}" -ne 0 ]]; then
    fail "run as root: sudo $0"
fi

for command_name in update-alternatives update-initramfs plymouth \
    awk grep cp mv rm mkdir mktemp chmod stat; do
    command -v "${command_name}" >/dev/null 2>&1 \
        || fail "required command not found: ${command_name}"
done

[[ -d "${SRC_DIR}" ]] || fail "source directory is not available: ${SRC_DIR}"
[[ -f "${SRC_DIR}/${THEME}.plymouth" && ! -L "${SRC_DIR}/${THEME}.plymouth" \
    && -s "${SRC_DIR}/${THEME}.plymouth" ]] \
    || fail "theme definition is missing or empty"
[[ -f "${SRC_DIR}/${THEME}.script" && ! -L "${SRC_DIR}/${THEME}.script" \
    && -s "${SRC_DIR}/${THEME}.script" ]] \
    || fail "theme script is missing or empty"
[[ -d "${SRC_DIR}/frames" && ! -L "${SRC_DIR}/frames" \
    && -s "${SRC_DIR}/frames/frame-1.png" ]] \
    || fail "animation frames are missing"
[[ -d "${SRC_DIR}/assets" && ! -L "${SRC_DIR}/assets" \
    && -s "${SRC_DIR}/assets/dot.png" \
    && -s "${SRC_DIR}/assets/progress.png" ]] \
    || fail "theme assets are missing"
[[ -d "${THEME_PARENT}" && ! -L "${THEME_PARENT}" ]] \
    || fail "Plymouth themes directory is missing or is a symbolic link"
[[ -d /usr/share/plymouth && ! -L /usr/share/plymouth ]] \
    || fail "Plymouth directory is missing or is a symbolic link"
[[ -d /var/lib && ! -L /var/lib ]] \
    || fail "/var/lib is missing or is a symbolic link"
[[ -d /boot && ! -L /boot ]] || fail "/boot is missing or is a symbolic link"
[[ ! -L "${DEST_DIR}" && ( ! -e "${DEST_DIR}" || ( -d "${DEST_DIR}" && -O "${DEST_DIR}" ) ) ]] \
    || fail "theme destination is not a root-owned directory"
[[ ( ! -e "${STATE_DIR}" && ! -L "${STATE_DIR}" ) \
    || ( -d "${STATE_DIR}" && ! -L "${STATE_DIR}" ) ]] \
    || fail "state path exists but is not a real directory"

INITIAL_QUERY=""
INITIAL_MODE=""
INITIAL_VALUE=""
INITIAL_REGISTERED=0
INITIAL_PRIORITY=""
if INITIAL_QUERY="$(query_alternatives)"; then
    ALTERNATIVE_LINK="$(awk '$1 == "Link:" { sub(/^Link: /, ""); print; exit }' \
        <<< "${INITIAL_QUERY}")"
    [[ "${ALTERNATIVE_LINK}" == "${ALTERNATIVE}" ]] \
        || fail "the default.plymouth alternative points to an unexpected path"
    INITIAL_MODE="$(awk '$1 == "Status:" { print $2; exit }' <<< "${INITIAL_QUERY}")"
    INITIAL_VALUE="$(awk '$1 == "Value:" { sub(/^Value: /, ""); print; exit }' \
        <<< "${INITIAL_QUERY}")"

    [[ "${INITIAL_MODE}" == "auto" || "${INITIAL_MODE}" == "manual" ]] \
        || fail "could not determine the current update-alternatives mode"
    [[ -n "${INITIAL_VALUE}" ]] \
        || fail "could not determine the currently selected Plymouth theme"
    if [[ "${INITIAL_MODE}" == "manual" ]] \
        && ! grep -Fqx "Alternative: ${INITIAL_VALUE}" <<< "${INITIAL_QUERY}"; then
        fail "manual Plymouth selection does not match a registered alternative"
    fi

    if grep -Fqx "Alternative: ${DEST_DIR}/${THEME}.plymouth" \
        <<< "${INITIAL_QUERY}"; then
        INITIAL_REGISTERED=1
        INITIAL_PRIORITY="$(awk -v target="${DEST_DIR}/${THEME}.plymouth" '
            $1 == "Alternative:" { alternative = $2; next }
            $1 == "Priority:" && alternative == target { print $2; exit }
        ' <<< "${INITIAL_QUERY}")"
        [[ "${INITIAL_PRIORITY}" =~ ^-?[0-9]+$ ]] \
            || fail "could not determine the installed theme alternative priority"
    fi
else
    query_status=$?
    if [[ "${query_status}" -eq 1 ]]; then
        INITIAL_MODE="auto"
        [[ ! -e "${ALTERNATIVE}" && ! -L "${ALTERNATIVE}" ]] \
            || fail "default.plymouth exists without an update-alternatives group"
    else
        fail "could not inspect Plymouth alternatives"
    fi
fi

if [[ -e "${STATE_DIR}" ]]; then
    [[ -O "${STATE_DIR}" ]] || fail "state directory is not owned by root"
    STATE_PERMISSIONS="$(stat -c '%a' "${STATE_DIR}")"
    [[ "${STATE_PERMISSIONS}" =~ ^[0-7]{3,4}$ ]] \
        || fail "could not validate state directory permissions"
    (( (8#${STATE_PERMISSIONS} & 0022) == 0 )) \
        || fail "state directory must not be group- or world-writable"
    [[ -f "${PREVIOUS_THEME}" && ! -L "${PREVIOUS_THEME}" ]] \
        || fail "saved state is incomplete; refusing to overwrite it"
    [[ -f "${PREVIOUS_MODE}" && ! -L "${PREVIOUS_MODE}" ]] \
        || fail "saved state is incomplete; refusing to infer the original alternatives mode"
    [[ -O "${PREVIOUS_THEME}" && -O "${PREVIOUS_MODE}" ]] \
        || fail "saved state files are not owned by root"
    for state_file in "${PREVIOUS_THEME}" "${PREVIOUS_MODE}"; do
        STATE_FILE_PERMISSIONS="$(stat -c '%a' "${state_file}")"
        [[ "${STATE_FILE_PERMISSIONS}" =~ ^[0-7]{3,4}$ ]] \
            || fail "could not validate permissions on saved state file ${state_file}"
        (( (8#${STATE_FILE_PERMISSIONS} & 0022) == 0 )) \
            || fail "saved state file is group- or world-writable: ${state_file}"
    done
    SAVED_MODE="$(<"${PREVIOUS_MODE}")"
    [[ "${SAVED_MODE}" == "auto" || "${SAVED_MODE}" == "manual" ]] \
        || fail "saved update-alternatives mode is invalid"
    SAVED_THEME="$(<"${PREVIOUS_THEME}")"
    [[ "${SAVED_THEME}" != *$'\n'* && "${SAVED_THEME}" != *$'\r'* ]] \
        || fail "saved Plymouth theme path is invalid"
else
    SAVED_MODE="${INITIAL_MODE}"
    if [[ -n "${INITIAL_QUERY}" ]]; then
        SAVED_THEME="${INITIAL_VALUE}"
    else
        SAVED_THEME=""
    fi
fi

shopt -s nullglob
INITRAMFS_FILES=(/boot/initrd.img-*)
shopt -u nullglob
((${#INITRAMFS_FILES[@]} > 0)) \
    || fail "no existing /boot/initrd.img-* files were found to update safely"
for initramfs_file in "${INITRAMFS_FILES[@]}"; do
    [[ -f "${initramfs_file}" && ! -L "${initramfs_file}" ]] \
        || fail "initramfs path is not a regular file: ${initramfs_file}"
done

BACKUP_DIR=""
STATE_STAGE=""
WORK_DIR=""
STATE_CREATED=0
DEST_EXISTED=0
DEST_SWAP_STARTED=0
ALTERNATIVES_ATTEMPTED=0
INITRAMFS_ATTEMPTED=0
TRANSACTION_STARTED=0
INSTALL_COMMITTED=0

rollback() {
    local rollback_failed=0
    local current_query=""
    local query_status=0
    local initrd_name=""
    local initrd_backup=""
    local initrd_target=""
    local restore_dir=""
    local restore_temp=""

    echo "Installation failed; restoring the previous configuration." >&2

    if [[ "${DEST_SWAP_STARTED}" -eq 1 ]]; then
        if [[ "${DEST_EXISTED}" -eq 1 && -e "${WORK_DIR}/previous-theme" ]]; then
            if [[ -e "${DEST_DIR}" || -L "${DEST_DIR}" ]] \
                && ! rm -rf -- "${DEST_DIR}"; then
                echo "Rollback error: could not remove the newly installed theme." >&2
                rollback_failed=1
            elif ! mv -T -- "${WORK_DIR}/previous-theme" "${DEST_DIR}"; then
                echo "Rollback error: could not restore the original theme files and permissions." >&2
                rollback_failed=1
            fi
        elif [[ "${DEST_EXISTED}" -eq 1 \
            && ( ! -e "${DEST_DIR}" && ! -L "${DEST_DIR}" ) ]]; then
            echo "Rollback error: the original theme directory and its backup are both missing." >&2
            rollback_failed=1
        elif [[ "${DEST_EXISTED}" -eq 0 \
            && ! -e "${WORK_DIR}/new-theme" \
            && ( -e "${DEST_DIR}" || -L "${DEST_DIR}" ) ]]; then
            if ! rm -rf -- "${DEST_DIR}"; then
                echo "Rollback error: could not remove the newly installed theme." >&2
                rollback_failed=1
            fi
        else
            :
        fi
    fi

    if [[ "${ALTERNATIVES_ATTEMPTED}" -eq 1 ]]; then
        if [[ "${INITIAL_REGISTERED}" -eq 1 ]]; then
            if ! LC_ALL=C update-alternatives --install "${ALTERNATIVE}" default.plymouth \
                "${THEME_FILE}" "${INITIAL_PRIORITY}"; then
                echo "Rollback error: could not restore the original alternative registration." >&2
                rollback_failed=1
            fi
        else
            if ! LC_ALL=C update-alternatives --remove default.plymouth "${THEME_FILE}"; then
                echo "Warning: update-alternatives did not remove the theme entry; verifying its state." >&2
            fi
        fi

        if current_query="$(query_alternatives)"; then
            :
        else
            query_status=$?
            if [[ "${query_status}" -eq 1 ]]; then
                current_query=""
            else
                echo "Rollback error: could not verify Plymouth alternative state." >&2
                current_query=""
                rollback_failed=1
            fi
        fi
        if [[ -n "${current_query}" ]]; then
            if [[ "${INITIAL_MODE}" == "auto" ]]; then
                if ! LC_ALL=C update-alternatives --auto default.plymouth; then
                    echo "Rollback error: could not restore automatic alternative selection." >&2
                    rollback_failed=1
                fi
            elif [[ "${INITIAL_MODE}" == "manual" ]] \
                && grep -Fqx "Alternative: ${INITIAL_VALUE}" <<< "${current_query}"; then
                if ! LC_ALL=C update-alternatives --set default.plymouth "${INITIAL_VALUE}"; then
                    echo "Rollback error: could not restore the previously selected theme." >&2
                    rollback_failed=1
                fi
            else
                echo "Rollback error: the previous manual theme is no longer registered; selection mode could not be restored." >&2
                if ! LC_ALL=C update-alternatives --auto default.plymouth; then
                    echo "Rollback error: automatic fallback selection also failed." >&2
                fi
                rollback_failed=1
            fi
        elif [[ -n "${INITIAL_QUERY}" ]]; then
            echo "Rollback error: the previous Plymouth alternatives group no longer exists." >&2
            rollback_failed=1
        fi
    fi

    if [[ "${INITRAMFS_ATTEMPTED}" -eq 1 ]]; then
        for initramfs_file in "${INITRAMFS_FILES[@]}"; do
            initrd_name="${initramfs_file##*/}"
            initrd_backup="${BACKUP_DIR}/initramfs/${initrd_name}"
            initrd_target="/boot/${initrd_name}"

            if [[ ! -f "${initrd_backup}" ]]; then
                echo "Rollback error: initramfs backup is missing for ${initrd_name}." >&2
                rollback_failed=1
                continue
            fi
            if [[ -L "${initrd_target}" ]]; then
                echo "Rollback error: refusing to overwrite a symbolic-link initramfs: ${initrd_target}" >&2
                rollback_failed=1
                continue
            fi
            if ! restore_dir="$(mktemp -d "/boot/.${THEME}.restore.XXXXXX")"; then
                echo "Rollback error: could not create a temporary initramfs restore directory." >&2
                rollback_failed=1
                continue
            fi
            restore_temp="${restore_dir}/${initrd_name}"
            if ! cp -a -- "${initrd_backup}" "${restore_temp}" \
                || ! mv -f -- "${restore_temp}" "${initrd_target}"; then
                echo "Rollback error: could not restore ${initrd_target}." >&2
                rollback_failed=1
            fi
            if ! rm -rf -- "${restore_dir}"; then
                echo "Rollback error: could not remove temporary restore directory ${restore_dir}." >&2
                rollback_failed=1
            fi
        done
    fi

    if [[ "${rollback_failed}" -eq 0 ]]; then
        if [[ "${STATE_CREATED}" -eq 1 ]] && ! rm -rf -- "${STATE_DIR}"; then
            echo "Rollback error: could not remove newly created saved state." >&2
            rollback_failed=1
        fi
        if [[ -n "${STATE_STAGE}" && -e "${STATE_STAGE}" ]] \
            && ! rm -rf -- "${STATE_STAGE}"; then
            echo "Rollback error: could not remove temporary saved state." >&2
            rollback_failed=1
        fi
    fi

    if [[ "${rollback_failed}" -eq 0 ]]; then
        if [[ -n "${BACKUP_DIR}" ]] && ! rm -rf -- "${BACKUP_DIR}"; then
            echo "Rollback error: could not remove temporary backups at ${BACKUP_DIR}." >&2
            rollback_failed=1
        fi
        if [[ -n "${WORK_DIR}" ]] && ! rm -rf -- "${WORK_DIR}"; then
            echo "Rollback error: could not remove temporary files at ${WORK_DIR}." >&2
            rollback_failed=1
        fi
    fi

    if [[ "${rollback_failed}" -ne 0 ]]; then
        echo "Rollback is incomplete; temporary recovery data was retained where possible." >&2
        return 1
    fi
    return 0
}

finish() {
    local exit_status=$?
    trap - EXIT
    trap '' INT TERM

    if [[ "${INSTALL_COMMITTED}" -eq 1 ]]; then
        if [[ -n "${BACKUP_DIR}" ]] && ! rm -rf -- "${BACKUP_DIR}"; then
            echo "Error: installation completed, but temporary backup cleanup failed: ${BACKUP_DIR}" >&2
            exit 1
        fi
        if [[ -n "${WORK_DIR}" ]] && ! rm -rf -- "${WORK_DIR}"; then
            echo "Error: installation completed, but temporary file cleanup failed: ${WORK_DIR}" >&2
            exit 1
        fi
        exit "${exit_status}"
    fi

    if [[ "${TRANSACTION_STARTED}" -eq 1 ]]; then
        if ! rollback; then
            echo "Recovery data retained; inspect ${STATE_DIR}, ${BACKUP_DIR:-no backup directory}, and ${WORK_DIR:-no work directory}." >&2
        fi
    fi
    exit "${exit_status:-1}"
}

trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

TRANSACTION_STARTED=1
if [[ ! -e "${STATE_DIR}" ]]; then
    STATE_STAGE="$(mktemp -d "/var/lib/.${THEME}.state.XXXXXX")"
    chmod 700 "${STATE_STAGE}"
    printf '%s\n' "${SAVED_THEME}" > "${STATE_STAGE}/previous-default.plymouth"
    printf '%s\n' "${SAVED_MODE}" > "${STATE_STAGE}/previous-alternatives-mode"
    mv -T -- "${STATE_STAGE}" "${STATE_DIR}"
    STATE_STAGE=""
    STATE_CREATED=1
fi

BACKUP_DIR="$(mktemp -d "/var/lib/.${THEME}.install.XXXXXX")"
mkdir -p "${BACKUP_DIR}/initramfs"
for initramfs_file in "${INITRAMFS_FILES[@]}"; do
    cp -a -- "${initramfs_file}" "${BACKUP_DIR}/initramfs/"
done

WORK_DIR="$(mktemp -d "${THEME_PARENT}/.${THEME}.install.XXXXXX")"
mkdir "${WORK_DIR}/new-theme"
cp -a -- "${SRC_DIR}/${THEME}.plymouth" "${SRC_DIR}/${THEME}.script" \
    "${SRC_DIR}/frames" "${SRC_DIR}/assets" "${WORK_DIR}/new-theme/"
if [[ -f "${SRC_DIR}/${THEME}.grub" ]]; then
    [[ ! -L "${SRC_DIR}/${THEME}.grub" ]] || fail "GRUB theme file must not be a symbolic link"
    cp -a -- "${SRC_DIR}/${THEME}.grub" "${WORK_DIR}/new-theme/"
fi
[[ -s "${WORK_DIR}/new-theme/${THEME}.plymouth" \
    && -s "${WORK_DIR}/new-theme/${THEME}.script" ]] \
    || fail "staged theme definition or script is missing"

DEST_SWAP_STARTED=1
if [[ -e "${DEST_DIR}" ]]; then
    DEST_EXISTED=1
    mv -T -- "${DEST_DIR}" "${WORK_DIR}/previous-theme"
fi
mv -T -- "${WORK_DIR}/new-theme" "${DEST_DIR}"

echo "==> Registering theme with update-alternatives"
ALTERNATIVES_ATTEMPTED=1
LC_ALL=C update-alternatives --install "${ALTERNATIVE}" default.plymouth \
    "${THEME_FILE}" 200

echo "==> Selecting theme as default"
LC_ALL=C update-alternatives --set default.plymouth "${THEME_FILE}"

echo "==> Rebuilding initramfs"
INITRAMFS_ATTEMPTED=1
update-initramfs -u

INSTALL_COMMITTED=1
echo
echo "Done! Theme '${THEME}' has been installed and activated."
echo "To test without rebooting:"
echo "    sudo plymouthd; sudo plymouth --show-splash; sleep 15; sudo plymouth quit"
