#!/bin/sh

set -e

usage() {
    cat >&2 <<EOF
Usage: ${0} [mode] [prompt]

Modes: boot, shutdown, reboot, suspend, resume, hibernate, thaw
Use "prompt" after the mode to test password and question dialogs.
The mode defaults to "boot".

Examples:
  ${0}
  ${0} shutdown
  ${0} boot prompt
  ${0} prompt
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "${1:-}" = "help" ]; then
    usage
    exit 0
fi

mode="${1:-boot}"
show_prompt="${2:-}"

# Keep the previous shorthand: "prompt" means boot mode with dialogs.
if [ "${mode}" = "prompt" ]; then
    mode="boot"
    show_prompt="prompt"
fi

case "${mode}" in
    boot|shutdown|reboot|suspend|resume|hibernate|thaw) ;;
    *)
        echo "Invalid mode: ${mode}" >&2
        usage
        exit 2
        ;;
esac

if [ -n "${show_prompt}" ] && [ "${show_prompt}" != "prompt" ]; then
    echo "Invalid option: ${show_prompt}" >&2
    usage
    exit 2
fi

if [ "$(id -u)" != "0" ]; then
    exec sudo "${0}" "${@}"
fi

plymouth_started=0
cleanup() {
    exit_status=$?
    trap - EXIT
    if [ "${plymouth_started}" -eq 1 ] && ! plymouth quit; then
        echo "Warning: could not stop Plymouth cleanly; run 'sudo plymouth quit'." >&2
    fi
    exit "${exit_status}"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 129' HUP
trap 'exit 143' TERM

set -x

plymouthd --mode="${mode}"
plymouth_started=1

plymouth --show-splash
if [ "${show_prompt}" = "prompt" ]; then
    plymouth ask-for-password --prompt="Enter a password"
    plymouth ask-question --command=cat --prompt="Say a few words"
fi
sleep 1
plymouth display-message \
    --text="Sample status or error text for display to the user"

for i in $(seq 1 10); do
    plymouth --update="Reticulating splines ${i}"
    sleep 1
done