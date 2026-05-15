#!/bin/bash
# ==============================================================================
#   Module:    gestures.sh
#   Purpose:   ChromeOS-like multi-finger touchpad gestures via touchegg
#              (pinch zoom, 3/4-finger swipes for back/forward, overview,
#              show-desktop, workspaces, whisker menu).
#   Reads:     REPO_DIR/assets/configs/touchegg.conf
#              SUDO_USER (optional, for live-session client)
#              helpers: ensure_apt_fresh
#   Writes:    apt: wmctrl, xdotool, touchegg, xfdashboard (optional)
#              /etc/touchegg/touchegg.conf
#              systemd: enables + starts touchegg.service
#              runs: touchegg --client for SUDO_USER (background)
#   Step fn:   step_gestures
#   Docs:      docs/modules/gestures.md
#   Uninstall: step_uninstall stops touchegg + kills clients (sub-step 1),
#              purges touchegg/xfdashboard/wmctrl/xdotool (sub-step 2),
#              removes /etc/touchegg/touchegg.conf and the touchegg client
#              autostart entry in skel and per-user (sub-steps 7, 12, 13).
#
#   NOTE: WHY TOUCHEGG, NOT libinput-gestures? touchegg runs the libinput
#   reader as a SYSTEM service and dispatches to per-user clients over
#   D-Bus, so no buyer needs to be added to the `input` group after
#   handover. xfdashboard is upstream-deprecated and may be absent from
#   newer Mint repos; its install failure is tolerated and the 3-finger
#   swipe-up gesture silently no-ops in that case.
# ==============================================================================

step_gestures() {
    echo "--> Installing ChromeOS-like touchpad gestures (touchegg)..."

    ensure_apt_fresh

    # Required gesture helpers + touchegg itself. We use the apt-packaged
    # touchegg (Mint repos carry a recent enough version) rather than juggling
    # GitHub release filenames whose names include the upstream version number.
    apt-get install -y wmctrl xdotool touchegg

    # xfdashboard is the XFCE "window overview" used by the 3-finger swipe up
    # gesture. It has been deprecated upstream and is missing from some
    # newer Mint releases — tolerate that. If absent, the gesture is a no-op.
    if ! apt-get install -y xfdashboard; then
        echo "    [!] xfdashboard not available in apt — 3-finger swipe up gesture"
        echo "        will silently no-op. Everything else (zoom, back/forward,"
        echo "        workspaces, show-desktop, whisker-menu) still works."
    fi

    # -------------------------------------------------------------------------
    # Deploy ChromeOS-like binding profile (system-wide)
    # -------------------------------------------------------------------------
    mkdir -p /etc/touchegg
    install -m 644 "$REPO_DIR/assets/configs/touchegg.conf" \
                   /etc/touchegg/touchegg.conf
    echo "    [+] /etc/touchegg/touchegg.conf written."

    # -------------------------------------------------------------------------
    # Enable the system daemon (per-user clients connect to it over D-Bus)
    # -------------------------------------------------------------------------
    systemctl enable --now touchegg.service 2>/dev/null || true
    if systemctl is-active --quiet touchegg.service; then
        echo "    [+] touchegg.service is active."
    else
        echo "    [!] touchegg.service is NOT active — gestures will not work until it starts."
    fi

    # -------------------------------------------------------------------------
    # Live oem session — start the client so the technician can verify
    # gestures during QA before handover. New users get the client via the
    # skel autostart (.config/autostart/touchegg-client.desktop).
    # -------------------------------------------------------------------------
    if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null; then
        local USER_HOME
        USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

        sudo -u "$SUDO_USER" pkill -f 'touchegg --client' 2>/dev/null || true
        sudo -u "$SUDO_USER" \
            DISPLAY="${DISPLAY:-:0}" \
            XAUTHORITY="$USER_HOME/.Xauthority" \
            touchegg --client 2>/dev/null &

        echo "    [+] touchegg client started for $SUDO_USER."
    else
        echo "    [i] \$SUDO_USER not set — client autostart on next login only."
    fi
}
