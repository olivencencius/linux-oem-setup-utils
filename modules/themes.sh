#!/bin/bash
# ==============================================================================
#   Module:    themes.sh
#   Purpose:   ChromeOS-like layout polish: Plank dock (bottom-centre) seeded
#              per-user by oem-first-run.sh, Malta wallpaper, and /etc/skel
#              staging (autostart). Does not override GTK/icon themes — distro
#              defaults apply (Xubuntu LTS compatible).
#   Reads:     REPO_DIR/assets/wallpapers/malta.jpg
#              REPO_DIR/assets/scripts/oem-first-run.sh
#              REPO_DIR/assets/scripts/oem-prepare-shipping.sh
#              REPO_DIR/assets/configs/oem-prepare-shipping.desktop
#              REPO_DIR/skel/...
#              SUDO_USER (optional, for live-session apply)
#              helpers: ensure_apt_fresh
#   Writes:    apt: plank, oem-config, oem-config-gtk
#              /usr/share/backgrounds/oem-setup/malta.jpg
#              /usr/local/bin/oem-first-run.sh       (mode 755)
#              /usr/local/bin/oem-prepare-shipping   (mode 755)
#              /usr/share/applications/oem-prepare-shipping.desktop
#              /etc/skel/...                         (full skel tree copy + Desktop launcher)
#              ~SUDO_USER/.config/autostart          (mirrored from skel)
#              ~SUDO_USER/Desktop/oem-prepare-shipping.desktop
#              ~SUDO_USER/.config/plank/dock1/...    (written by inline
#                                                     oem-first-run.sh call)
#   Step fn:   step_themes
#   Helpers:   oem_user_xrun (file-scope)
#   Docs:      docs/modules/themes.md
#   Uninstall: step_uninstall purges plank + oem-config packages (sub-step 2),
#              removes wallpaper + first-run script (sub-step 7), scrubs
#              /etc/skel (sub-step 11), and cleans per-user plank config +
#              marker (sub-step 12).
#
#   NOTE — why Plank (not a 2nd XFCE panel). Xubuntu's primary panel often runs
#   along one long edge; a second centred XFCE panel on that edge collides.
#   Plank is a separate floating window so it co-exists cleanly. It is one apt
#   package in main/Ubuntu repos.
# ==============================================================================

# ------------------------------------------------------------------------------
# Helper — run an X11 / xfconf command as the live oem user with the right
# DISPLAY / XAUTHORITY / DBUS_SESSION_BUS_ADDRESS so xfconfd can be reached.
# Returns the command's exit status; callers add `|| true` if they don't care.
# ------------------------------------------------------------------------------
oem_user_xrun() {
    local user="$1"; shift
    local home dbus_addr
    home=$(getent passwd "$user" | cut -d: -f6)

    local pid
    pid=$(pgrep -u "$user" -x xfsettingsd 2>/dev/null | head -1 || true)
    [ -z "$pid" ] && pid=$(pgrep -u "$user" -x xfce4-session 2>/dev/null | head -1 || true)

    if [ -n "$pid" ] && [ -r "/proc/$pid/environ" ]; then
        dbus_addr=$(tr '\0' '\n' < "/proc/$pid/environ" \
                    | awk '/^DBUS_SESSION_BUS_ADDRESS=/{ print substr($0, index($0,"=")+1); exit }' || true)
    fi

    sudo -u "$user" env \
        HOME="$home" \
        USER="$user" \
        LOGNAME="$user" \
        PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        DISPLAY="${DISPLAY:-:0}" \
        XAUTHORITY="$home/.Xauthority" \
        DBUS_SESSION_BUS_ADDRESS="${dbus_addr:-}" \
        "$@"
}

step_themes() {
    local SUDO_HOME

    oem_tty_say "--> Installing Plank (dock)…"

    ensure_apt_fresh
    oem_run_log env DEBIAN_FRONTEND=noninteractive apt-get install -y plank
    oem_tty_say "    [+] plank installed."

    oem_tty_say "--> Installing Ubuntu OEM handover packages (oem-config)…"
    oem_run_log env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        oem-config oem-config-gtk
    oem_tty_say "    [+] oem-config packages installed."

    install -m 755 "$REPO_DIR/assets/scripts/oem-prepare-shipping.sh" \
                   /usr/local/bin/oem-prepare-shipping
    oem_tty_say "    [+] /usr/local/bin/oem-prepare-shipping deployed."

    install -m 644 "$REPO_DIR/assets/configs/oem-prepare-shipping.desktop" \
                   /usr/share/applications/oem-prepare-shipping.desktop
    oem_tty_say "    [+] /usr/share/applications/oem-prepare-shipping.desktop deployed."

    oem_tty_say "--> Installing wallpaper…"
    mkdir -p /usr/share/backgrounds/oem-setup
    cp "$REPO_DIR/assets/wallpapers/malta.jpg" \
       /usr/share/backgrounds/oem-setup/malta.jpg
    oem_tty_say "    [+] /usr/share/backgrounds/oem-setup/malta.jpg deployed."

    install -m 755 "$REPO_DIR/assets/scripts/oem-first-run.sh" \
                   /usr/local/bin/oem-first-run.sh
    oem_tty_say "    [+] /usr/local/bin/oem-first-run.sh deployed."

    oem_tty_say "--> Staging defaults into /etc/skel…"
    cp -r "$REPO_DIR/skel/." /etc/skel/
    mkdir -p /etc/skel/Desktop
    cp -f "$REPO_DIR/assets/configs/oem-prepare-shipping.desktop" \
       /etc/skel/Desktop/oem-prepare-shipping.desktop
    chmod 644 /etc/skel/Desktop/oem-prepare-shipping.desktop

    if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null; then
        SUDO_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

        oem_tty_say "--> Mirroring skel autostart into live user's home: $SUDO_USER"

        sudo -u "$SUDO_USER" mkdir -p "$SUDO_HOME/.config/autostart"

        for f in oem-first-run.desktop; do
            if [ -f "/etc/skel/.config/autostart/$f" ]; then
                cp "/etc/skel/.config/autostart/$f" \
                   "$SUDO_HOME/.config/autostart/$f"
            fi
        done

        chown -R "$SUDO_USER:$SUDO_USER" "$SUDO_HOME/.config/autostart"

        oem_tty_say "--> Mirroring OEM handover desktop launcher into ~$SUDO_USER/Desktop…"
        sudo -u "$SUDO_USER" mkdir -p "$SUDO_HOME/Desktop"
        cp -f /etc/skel/Desktop/oem-prepare-shipping.desktop \
           "$SUDO_HOME/Desktop/oem-prepare-shipping.desktop"
        chown "$SUDO_USER:$SUDO_USER" "$SUDO_HOME/Desktop/oem-prepare-shipping.desktop"

        oem_tty_say "--> Running oem-first-run.sh once for the live session (Plank + wallpaper)…"
        oem_user_xrun "$SUDO_USER" /usr/local/bin/oem-first-run.sh 2>/dev/null || true

        oem_tty_say "    [+] Wallpaper and Plank dock applied to live session for user: $SUDO_USER"
    else
        oem_tty_say "    [i] \$SUDO_USER not set — layout will apply on next login via skel."
    fi
}
