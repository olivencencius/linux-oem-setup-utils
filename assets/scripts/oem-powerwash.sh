#!/bin/bash
# ==============================================================================
#   Script:       oem-powerwash.sh
#   Purpose:      User-facing entry point for Powerwash. Drives two zenity
#                 confirmations (yes/no + typed POWERWASH), then pkexec-
#                 escalates to oem-powerwash-arm.sh which writes the flag the
#                 boot-time finalize service consumes.
#   Installed to: /usr/local/bin/oem-powerwash.sh    (mode 755)
#   Installed by: modules/powerwash.sh
#   Runs as:      the buyer (unprivileged); refuses to run as root because
#                 the GUI dialogs must own the user's X session.
#   Triggered by: /usr/share/applications/oem-powerwash.desktop (menu entry)
#   Reads:        DISPLAY or WAYLAND_DISPLAY (to choose zenity vs TTY fallback)
#   Writes:       (nothing directly — escalates to arm script via pkexec)
#   Stage flow:   1) zenity --question (Continue / Cancel)
#                 2) zenity --entry    (must type POWERWASH)
#                 3) pkexec /usr/local/sbin/oem-powerwash-arm.sh
#                    on success: backgrounded zenity --info "restarting…"
#                    on failure: zenity --error and exit
#   Uninstall:    step_uninstall (sub-step 8b) removes this script.
#   Docs:         docs/powerwash.md (end-to-end flow)
#
#   NOTE: "device will restart now" is shown ONLY after pkexec returns 0.
#   Showing it earlier would lie to a buyer who cancels admin auth.
# ==============================================================================

set -u

# Refuse to run as root — the GUI dialogs must own the user's X session.
if [ "$(id -u)" = "0" ]; then
    echo "oem-powerwash: do not run this script as root." >&2
    echo "It is launched from the application menu and escalates itself only" >&2
    echo "when the buyer confirms the powerwash." >&2
    exit 1
fi

# Pick a dialog backend: zenity if a display is available, plain TTY otherwise.
USE_GUI=0
if command -v zenity >/dev/null 2>&1 \
   && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then
    USE_GUI=1
fi

WARNING_HTML='<b>Powerwash will erase ALL personal data on this device.</b>

This includes:
  • Every user account and its files (Documents, Pictures, Downloads, …)
  • Every browser profile, saved password and bookmark
  • Every application installed under your account

The factory configuration is preserved:
  • Drivers and hardware fixes
  • Desktop theme, dock, wallpaper and shortcuts
  • Language packs and keyboard layout
  • All system-wide applications

After the device restarts, you will be guided through the same
welcome wizard you saw when you first received this laptop.

This action <b>cannot be undone</b>. Continue?'

WARNING_TXT='Powerwash will erase ALL personal data on this device:
  - Every user account and its files
  - Every browser profile and saved password
  - Every application installed under your account
The factory configuration is preserved. This cannot be undone.'

# ------------------------------------------------------------------------------
# Stage 1 — broad warning + yes/no
# ------------------------------------------------------------------------------
if [ "$USE_GUI" = "1" ]; then
    zenity --question \
           --title="Powerwash this device" \
           --width=520 \
           --ok-label="Continue" \
           --cancel-label="Cancel" \
           --text="$WARNING_HTML" \
           2>/dev/null || exit 0
else
    echo "$WARNING_TXT"
    read -r -p "Type 'continue' to proceed: " ans
    [ "$ans" = "continue" ] || { echo "Powerwash cancelled."; exit 0; }
fi

# ------------------------------------------------------------------------------
# Stage 2 — typed-phrase confirmation
# ------------------------------------------------------------------------------
if [ "$USE_GUI" = "1" ]; then
    typed=$(zenity --entry \
                   --title="Confirm powerwash" \
                   --width=520 \
                   --text="Type the word <b>POWERWASH</b> (in capital letters) to start." \
                   2>/dev/null) || exit 0
else
    read -r -p "Type POWERWASH to start, anything else to cancel: " typed
fi

if [ "$typed" != "POWERWASH" ]; then
    if [ "$USE_GUI" = "1" ]; then
        zenity --info --width=320 --text="Powerwash cancelled." 2>/dev/null
    fi
    echo "Powerwash cancelled."
    exit 0
fi

# ------------------------------------------------------------------------------
# Stage 3 — escalate via pkexec to arm the boot-time finalize step.
#
#   The polkit policy at
#     /usr/share/polkit-1/actions/org.linuxoem.powerwash.policy
#   gates this with the standard admin auth dialog. If the buyer
#   cancels that dialog, pkexec returns 127 and we report it; we do
#   NOT pre-emptively show the "device will restart" notice.
# ------------------------------------------------------------------------------
if pkexec /usr/local/sbin/oem-powerwash-arm.sh; then
    # Arm succeeded — it will reboot the machine in ~2 seconds.
    if [ "$USE_GUI" = "1" ]; then
        zenity --info \
               --title="Powerwash" \
               --width=440 \
               --text="The device will restart now to finish powerwashing.\n\nDo not power off until the setup wizard appears." \
               2>/dev/null &
    fi
    exit 0
else
    rc=$?
    if [ "$USE_GUI" = "1" ]; then
        zenity --error \
               --title="Powerwash cancelled" \
               --width=440 \
               --text="Powerwash was not started (admin authentication required, or arm step failed). No changes have been made." \
               2>/dev/null
    fi
    echo "Powerwash cancelled or arm step failed (pkexec exit $rc)."
    exit "$rc"
fi
