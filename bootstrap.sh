#!/bin/bash
# ==============================================================================
#   Lubuntu Chromebook OEM Bootstrap
# ==============================================================================
set -euo pipefail

if [ "${EUID:-}" -ne 0 ]; then
    echo "Error: Please run this script with sudo (root privileges required)."
    exit 1
fi

readonly GITHUB_RAW="https://raw.githubusercontent.com/olivencencius/linux-oem-setup-utils/main"
readonly WORK_DIR="/tmp/lubuntu-oem-setup"
readonly STATE_DIR="/var/lib/lubuntu-oem-setup"
readonly STATE_FILE="${STATE_DIR}/.state"
readonly LOG_FILE="/var/log/lubuntu_oem_setup.log"

MODULES=(
    "01_update_os.sh"
    "02_install_git.sh"
    "03_boot_optimization.sh"
    "04_chromebook_fixes.sh"
    "05_touchpad_gestures.sh"
    "06_workspaces_view.sh"
    "07_terminal_paste_fix.sh"
    "08_install_chrome.sh"
    "09_install_vlc.sh"
    "10_web_apps.sh"
    "11_install_games.sh"
    "12_install_plank.sh"
    "13_touchpad_scroll_speed.sh"
    "15_lid_close_suspend.sh"
)

ADDONS=(
    "diagnostics.sh"
)

mkdir -p "$WORK_DIR" "$STATE_DIR"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

export STATE_DIR STATE_FILE LOG_FILE WORK_DIR

log_msg() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

is_step_done() {
    local step="$1"
    [ -f "$STATE_FILE" ] && grep -qxF "$step" "$STATE_FILE"
}

mark_step_done() {
    local step="$1"
    grep -qxF "$step" "$STATE_FILE" 2>/dev/null || echo "$step" >> "$STATE_FILE"
}

download_modules() {
    log_msg "Downloading modules to ${WORK_DIR}…"
    local f base
    for f in "${MODULES[@]}"; do
        base="${f%.sh}"
        log_msg "  -> ${f}"
        wget -q --show-progress -O "${WORK_DIR}/${f}" "${GITHUB_RAW}/modules/${f}" \
            || wget -O "${WORK_DIR}/${f}" "${GITHUB_RAW}/modules/${f}"
        chmod +x "${WORK_DIR}/${f}"
    done
    log_msg "All modules downloaded."
}

download_addons() {
    log_msg "Downloading add-ons to ${WORK_DIR}/addons…"
    mkdir -p "${WORK_DIR}/addons"
    local f
    for f in "${ADDONS[@]}"; do
        log_msg "  -> addons/${f}"
        wget -q --show-progress -O "${WORK_DIR}/addons/${f}" "${GITHUB_RAW}/addons/${f}" \
            || wget -O "${WORK_DIR}/addons/${f}" "${GITHUB_RAW}/addons/${f}"
        chmod +x "${WORK_DIR}/addons/${f}"
    done
    log_msg "All add-ons downloaded."
}

run_module() {
    local script="$1"
    local step_id="${script%.sh}"

    if is_step_done "$step_id"; then
        log_msg "[${step_id}] Already completed — skipping."
        return 0
    fi

    log_msg "========== Running ${script} =========="
    if bash "${WORK_DIR}/${script}"; then
        mark_step_done "$step_id"
        log_msg "[${step_id}] Completed successfully."
        return 0
    else
        log_msg "[${step_id}] FAILED (exit $?). Fix the issue and re-run; completed steps are skipped."
        return 1
    fi
}

run_addon() {
    local script="$1"
    log_msg "========== Running add-on ${script} =========="
    if bash "${WORK_DIR}/addons/${script}"; then
        log_msg "[addon:${script%.sh}] Completed successfully."
        return 0
    else
        log_msg "[addon:${script%.sh}] FAILED (exit $?)."
        return 1
    fi
}

run_pipeline() {
    local script failed=0
    for script in "${MODULES[@]}"; do
        run_module "$script" || failed=1
    done
    if [ "$failed" -eq 0 ]; then
        log_msg "Pipeline finished — all modules completed."
    else
        log_msg "Pipeline stopped with errors. Re-run bootstrap to resume."
        return 1
    fi
}

show_menu() {
    echo ""
    echo "========================================="
    echo "   LUBUNTU CHROMEBOOK OEM SETUP"
    echo "========================================="
    echo "  Log file: ${LOG_FILE}"
    echo "  State:    ${STATE_FILE}"
    echo ""
    echo "  0) Run full pipeline (modules 1–13, 15)"
    echo "  1)  OS update & Codecs"
    echo "  2)  Install git"
    echo "  3)  Boot optimization"
    echo "  4)  Chromebook fixes (audio, keyboard, ZRAM)"
    echo "  5)  Touchpad + gestures"
    echo "  6)  Workspaces overview (skippy-xd)"
    echo "  7)  Terminal paste fix"
    echo "  8)  Install Google Chrome"
    echo "  9)  Install VLC"
    echo " 10)  Web apps"
    echo " 11)  Low-spec games"
    echo " 12)  Plank dock & Panel move"
    echo " 13)  Touchpad scroll speed (libinput ScrollPixelDistance)"
    echo " 15)  Lid close: deep sleep + suspend on lid"
    echo ""
    echo "  Add-ons (standalone):"
    echo "  d)  Hardware diagnostics (read-only report)"
    echo ""
    echo "  q) Quit"
    echo ""
}

main() {
    log_msg "Bootstrap started."
    download_modules
    download_addons

    while true; do
        show_menu
        read -r -p "Select option [0-13, 15, d, q]: " choice </dev/tty || choice="q"

        case "$choice" in
            0) run_pipeline ;;
            1|2|3|4|5|6|7|8|9|10|11|12|13)
                idx=$((10#$choice))
                run_module "${MODULES[$((idx - 1))]}"
                ;;
            15) run_module "15_lid_close_suspend.sh" ;;
            d|D) run_addon "diagnostics.sh" ;;
            q|Q)
                log_msg "Bootstrap exited by user."
                exit 0
                ;;
            *) echo "Invalid option. Try again." ;;
        esac
    done
}

main "$@"