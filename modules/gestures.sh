#!/bin/bash
# ==============================================================================
#   Module:    gestures.sh
#   Purpose:   ChromeOS-like multi-finger touchpad gestures via touchegg
#              (pinch zoom, 3/4-finger swipes for back/forward, overview,
#              show-desktop, workspaces, whisker menu), plus xfdashboard
#              workspace/window overview and a system launcher for Plank.
#   Reads:     REPO_DIR/assets/configs/touchegg.conf
#              REPO_DIR/assets/configs/oem-workspace-overview.desktop
#              SUDO_USER (optional, for live-session client)
#              helpers: ensure_apt_fresh
#   Writes:    apt: wmctrl, xdotool, touchegg, xfdashboard
#              /usr/share/applications/oem-workspace-overview.desktop
#              /etc/touchegg/touchegg.conf
#              systemd: enables + starts touchegg.service
#              runs: touchegg --client for SUDO_USER (background)
#   Step fn:   step_gestures_and_workspaces
#   Docs:      docs/modules/gestures.md
#   Uninstall: step_uninstall stops touchegg + kills clients (sub-step 1),
#              purges touchegg/xfdashboard/wmctrl/xdotool (sub-step 2),
#              removes /etc/touchegg/touchegg.conf, oem-workspace-overview.desktop,
#              and the touchegg client autostart entry in skel and per-user
#              (sub-steps 7, 8, 12, 13).
#
#   NOTE: WHY TOUCHEGG, NOT libinput-gestures? touchegg runs the libinput
#   reader as a SYSTEM service and dispatches to per-user clients over
#   D-Bus, so no buyer needs to be added to the `input` group after
#   handover. xfdashboard is the Xfce window/workspace overview for the
#   3-finger swipe-up gesture and the Plank “overview” pin; it must be
#   installed before step_themes runs oem-first-run.sh so the dockitem exists.
# ==============================================================================

step_gestures_and_workspaces() {
    oem_tty_say "--> Installing touchpad gestures (touchegg) and workspace overview (xfdashboard)…"

    ensure_apt_fresh

    # apt exit 100 = install failure; errors must be visible (same TTY issue as Chrome wget).
    oem_tty_say \
        "--> apt: installing wmctrl, xdotool, touchegg, xfdashboard…" \
        "    [.] If this fails with exit 100, read the apt message below — often missing repo (enable \"universe\") or broken dpkg state (sudo dpkg --configure -a)."
    env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        wmctrl xdotool touchegg xfdashboard \
        </dev/null >&3 2>&3

    install -m 644 "$REPO_DIR/assets/configs/oem-workspace-overview.desktop" \
        /usr/share/applications/oem-workspace-overview.desktop
    oem_tty_say "    [+] /usr/share/applications/oem-workspace-overview.desktop"

    if command -v update-desktop-database &>/dev/null; then
        oem_run_log update-desktop-database /usr/share/applications 2>/dev/null || true
    fi

    # -------------------------------------------------------------------------
    # Deploy ChromeOS-like binding profile (system-wide)
    # -------------------------------------------------------------------------
    mkdir -p /etc/touchegg
    install -m 644 "$REPO_DIR/assets/configs/touchegg.conf" \
                   /etc/touchegg/touchegg.conf
    oem_tty_say "    [+] /etc/touchegg/touchegg.conf written."

    # -------------------------------------------------------------------------
    # Enable the system daemon (per-user clients connect to it over D-Bus)
    # -------------------------------------------------------------------------
    systemctl enable --now touchegg.service 2>/dev/null || true
    if systemctl is-active --quiet touchegg.service; then
        oem_tty_say "    [+] touchegg.service is active."
    else
        oem_tty_say "    [!] touchegg.service is NOT active — gestures will not work until it starts."
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

        oem_tty_say "    [+] touchegg client started for $SUDO_USER."
    else
        oem_tty_say "    [i] \$SUDO_USER not set — client autostart on next login only."
    fi

    # Legacy step id was `gestures`; drop its marker so resume matches setup.sh.
    rm -f "${STATE_DIR:-/var/lib/oem-setup/state}/gestures.done" 2>/dev/null || true
}
