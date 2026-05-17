#!/bin/bash
# ==============================================================================
#   Chromebook OEM Deployment Engine
#   Converts MrChromebox-flashed x86 Chromebooks into market-ready Linux
#   Xubuntu LTS machines optimised for resale. Run as root from the cloned repository.
#
#   Usage (recommended — single command, no pre-installed dependencies):
#     curl -sL https://raw.githubusercontent.com/olivencencius/linux-oem-setup-utils/main/bootstrap.sh | sudo bash
#
#   Or if the repo is already cloned locally:
#     sudo bash setup.sh
#
#   Resume after a crash / Ctrl-C:
#     sudo bash setup.sh   (completed steps are skipped automatically)
#
#   Force a clean re-run of everything:
#     sudo rm -rf /var/lib/oem-setup/state && sudo bash setup.sh
# ==============================================================================

set -Eeuo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run this script with sudo."
    exit 1
fi

# Resolve absolute path to this repo so all modules can reference assets/
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_DIR

# ==============================================================================
#   State + logging
#   - LOG_FILE   : best-effort transcript (stdout/stderr through `tee`; see below)
#   - STATE_DIR  : per-step "done" markers + saved keyboard layout
#
#   Priority: what you see in the terminal is authoritative. The log file
#   captures whatever flows through the shell's tee'd stdout — it does NOT
#   include output from `oem_run_interactive` (upstream audio/keyboard
#   installers), which attach directly to the real TTY so prompts work.
# ==============================================================================
LOG_FILE="/var/log/oem-setup.log"
STATE_DIR="/var/lib/oem-setup/state"
mkdir -p "$(dirname "$LOG_FILE")" "$STATE_DIR" /var/lib/oem-setup/backups
export STATE_DIR
export LOG_FILE

# Real terminal on fd 3. Plain `echo` without oem_tty_say can look "stuck" once
# stdout is a pipe to `tee` (libc fully buffers non-TTY stdout).
if ! exec 3<>/dev/tty 2>/dev/null; then
    exec 3>&2
fi

# Tee shell stdout/stderr into the log file and the terminal (best-effort copy).
exec > >(tee -a "$LOG_FILE") 2>&1

# Duplicate lines to fd 3 (real TTY) and stdout — libc fully buffers stdout once it
# is the `tee` pipe, so plain `echo` after prompts can appear to do nothing.
oem_tty_say() {
    printf '%s\n' "$@" >&3
    printf '%s\n' "$@"
}
export -f oem_tty_say

# Long-running commands (apt, wget, git, …): line-buffer through the `tee` pipe.
oem_run_log() {
    stdbuf -oL -eL "$@"
}
export -f oem_run_log

# Upstream installers (chromebook-linux-audio, cros-keyboard-map) need a real
# TTY on stdin/out/err — not the `tee` pipe — or prompts disappear. Log file
# only gets begin/end markers; the live session is intentionally terminal-only.
oem_run_interactive() {
    printf '%s\n' "$(date -Is) [interactive] START $*" >> "$LOG_FILE"
    "$@" <&3 >&3 2>&3
    local ec=$?
    printf '%s\n' "$(date -Is) [interactive] END (exit $ec) $*" >> "$LOG_FILE"
    return "$ec"
}
export -f oem_run_interactive

oem_tty_say "" "=== oem-setup run started: $(date -Iseconds) ==="

# ==============================================================================
#   backup_once — snapshot a system file before we mutate it for the first time
# ==============================================================================
backup_once() {
    local src="$1"
    local dst="/var/lib/oem-setup/backups/$(basename "$src")"
    if [ -e "$src" ] && [ ! -e "$dst" ]; then
        cp -a "$src" "$dst"
    fi
}
export -f backup_once

# ==============================================================================
#   ensure_apt_fresh — run `apt-get update` at most once per setup.sh invocation.
#   Modules that install packages call this so a stale cache doesn't bite us
#   even when the technician picks an individual menu option.
# ==============================================================================
ensure_apt_fresh() {
    if [ -z "${OEM_APT_FRESH:-}" ]; then
        oem_tty_say "    [.] Refreshing apt package index (apt-get update)…"
        oem_run_log apt-get update -qq || true
        export OEM_APT_FRESH=1
    fi
}
export -f ensure_apt_fresh

# ==============================================================================
#   Step state helpers
# ==============================================================================
mark_done() { touch "$STATE_DIR/$1.done"; }
is_done()   { [ -e "$STATE_DIR/$1.done" ]; }

# do_step <name>   — always run, mark done on success
# run_step <name>  — skip if marker exists, otherwise do_step
do_step() {
    local name="$1"
    CURRENT_STEP="$name"
    oem_tty_say "" "==> step_${name}  [$(date -Iseconds)]"
    "step_${name}"
    mark_done "$name"
    oem_tty_say "<== step_${name} OK"
}

run_step() {
    local name="$1"
    if is_done "$name"; then
        oem_tty_say "==> step_${name}  [skipped — already completed; rm $STATE_DIR/${name}.done to redo]"
        return 0
    fi
    do_step "$name"
}

# ==============================================================================
#   Error / interrupt handlers
#   Print the step that was running and where to look for details.
# ==============================================================================
on_err() {
    local exit_code=$?
    local line=$1
    oem_tty_say "" "================================================================="
    oem_tty_say "[!] FAILED at step: ${CURRENT_STEP:-<setup>}  (line $line, exit $exit_code)"
    oem_tty_say "[!] Log: $LOG_FILE"
    oem_tty_say "[!] Fix the cause, then re-run 'sudo bash setup.sh' — completed"
    oem_tty_say "    steps will be skipped automatically."
    oem_tty_say "================================================================="
    exit "$exit_code"
}
on_int() {
    oem_tty_say "" "================================================================="
    oem_tty_say "[!] Interrupted by user at step: ${CURRENT_STEP:-<setup>}"
    oem_tty_say "[!] Re-run 'sudo bash setup.sh' to resume."
    oem_tty_say "================================================================="
    exit 130
}
trap 'on_err $LINENO' ERR
trap on_int INT TERM

# ==============================================================================
#   Source all function modules
# ==============================================================================
source "$REPO_DIR/modules/cleanup.sh"
source "$REPO_DIR/modules/updates.sh"
source "$REPO_DIR/modules/hardware.sh"
source "$REPO_DIR/modules/xubuntu_boot.sh"
source "$REPO_DIR/modules/chrome.sh"
source "$REPO_DIR/modules/zoom.sh"
source "$REPO_DIR/modules/apps.sh"
source "$REPO_DIR/modules/webapps.sh"
source "$REPO_DIR/modules/themes.sh"
source "$REPO_DIR/modules/touchpad.sh"
source "$REPO_DIR/modules/gestures.sh"
source "$REPO_DIR/modules/terminal.sh"
source "$REPO_DIR/modules/regional.sh"
source "$REPO_DIR/modules/diagnostics.sh"
source "$REPO_DIR/modules/uninstall.sh"

# ==============================================================================
#   Full pipeline — uses run_step so completed steps are skipped on resume.
#   Order is intentional:
#     - prompt_keyboard FIRST so the rest can run unattended
#     - chrome + zoom + apps + web_apps BEFORE themes so the .desktop files
#       referenced by Plank already exist when /etc/skel is staged
#     - xubuntu_boot AFTER hardware_fixes so GRUB merges HPET + silent-boot tokens cleanly
#     - gestures_and_workspaces AFTER web_apps and BEFORE themes so xfdashboard
#       and oem-workspace-overview.desktop exist before oem-first-run.sh seeds Plank
# ==============================================================================
run_full_pipeline() {
    prompt_keyboard
    oem_tty_say "    [.] Keyboard choice recorded — continuing (terminal is live; log: $LOG_FILE)…"
    run_step cleanup
    run_step updates
    run_step hardware_fixes
    run_step xubuntu_boot
    run_step chrome
    run_step zoom
    run_step apps
    run_step web_apps
    run_step gestures_and_workspaces
    run_step themes
    run_step touchpad
    run_step terminal
    run_step regional
    run_step diagnostics
}

# ==============================================================================
#   Reboot reminder — called once the pipeline returns, before the OPERATION END
#   banner. Several steps (GRUB, initramfs, keyd, audio, locale) only take
#   full effect after a reboot, so we always warn.
# ==============================================================================
print_reboot_reminder() {
    oem_tty_say \
        "" \
        "=================================================================" \
        " REBOOT REQUIRED before QA — kernel/initramfs/audio/keyboard " \
        " changes only take full effect on the next boot." \
        "================================================================="
}

# ==============================================================================
#   Interactive menu — individual options ALWAYS run (via do_step), so the
#   technician can re-apply a step on demand even after a full pipeline.
# ==============================================================================
while true; do
    # Writes go to fd 3 (real terminal), not stdout — avoids full-buffer delays.
    {
        echo ""
        echo "========================================="
        echo "        CHROMEBOOK DEPLOYMENT ENGINE     "
        echo "========================================="
        echo " 1)  Run entire pipeline (recommended for fresh setup)"
        echo " 2)  Boot optimisations only (re-apply; also runs in option 1 pipeline)"
        echo " 3)  Run system updates and dependency installation"
        echo " 4)  Run Chromebook hardware fixes and patches"
        echo " 5)  Install Google Chrome"
        echo " 6)  Install Zoom"
        echo " 7)  Install standard apps (VLC + games)"
        echo " 8)  Inject branded web-app shortcuts"
        echo " 9)  Workspace overview, libinput-gestures, Plank dock and wallpaper"
        echo " 10) Apply touchpad calibration and scroll speed fix (libinput)"
        echo " 11) Libinput gestures + xfdashboard only (skips Plank / wallpaper)"
        echo " 12) Apply terminal paste fix"
        echo " 13) Adjust region, language and keyboard layout"
        echo " 14) Run hardware diagnostics report"
        echo " 15) Undo all changes (full uninstall)"
        echo " 16) Exit setup"
        echo "========================================="
        printf "Select choice [1-16] (type number, then press Enter): "
    } >&3
    read -r main_choice < /dev/tty || true
    main_choice=${main_choice:-}
    echo "" >&3

    case $main_choice in
        1)  run_full_pipeline; print_reboot_reminder; break ;;
        2)  do_step xubuntu_boot ;;
        3)  do_step cleanup; do_step updates ;;
        4)  do_step cleanup; do_step hardware_fixes ;;
        5)  do_step chrome ;;
        6)  do_step zoom ;;
        7)  do_step apps ;;
        8)  do_step web_apps ;;
        9)  do_step cleanup; do_step gestures_and_workspaces; do_step themes ;;
        10) do_step touchpad ;;
        11) do_step gestures_and_workspaces ;;
        12) do_step terminal ;;
        13) do_step regional ;;
        14) do_step diagnostics ;;
        15) step_uninstall ;;
        16) oem_tty_say "Exiting configuration engine."; exit 0 ;;
        *)  oem_tty_say "Invalid option. Please choose 1-16." ;;
    esac
done

oem_tty_say \
    "" \
    "=========================================" \
    "              OPERATION END              " \
    "=========================================" \
    "" \
    "REMINDER: Once you have rebooted and verified the setup, double-click" \
    "  'Prepare for shipping to end user' on the desktop (or run" \
    "  sudo oem-prepare-shipping), then shut down when the tool says you may." \
    "========================================="
