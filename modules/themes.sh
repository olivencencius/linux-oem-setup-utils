#!/bin/bash
# ==============================================================================
#   Module:    themes.sh
#   Purpose:   ChromeOS-like visual polish using fully Mint-shipped components:
#              Mint-Y-Aqua GTK theme (ships with mint-themes, always present),
#              Papirus icon theme (apt), and an XFCE bottom panel created as
#              a dock-style launcher bar by oem-first-run.sh.
#              Also handles: Malta wallpaper, per-user first-run script, and
#              the full /etc/skel staging.
#   Reads:     REPO_DIR/assets/wallpapers/malta.jpg
#              REPO_DIR/assets/scripts/oem-first-run.sh
#              REPO_DIR/skel/...
#              SUDO_USER (optional, for live-session apply)
#              helpers: ensure_apt_fresh
#   Writes:    apt: papirus-icon-theme, gtk2-engines-murrine
#              /usr/share/backgrounds/oem-setup/malta.jpg
#              /usr/local/bin/oem-first-run.sh       (mode 755)
#              /etc/skel/...                         (full skel tree copy)
#              ~SUDO_USER/.config/{autostart,xfce4}  (mirrored from skel so
#                                                     the live oem session
#                                                     gets the theme and
#                                                     wallpaper without a
#                                                     re-login)
#   Step fn:   step_themes
#   Helpers:   oem_user_xrun (file-scope)
#   Docs:      docs/modules/themes.md
#   Uninstall: step_uninstall purges papirus-icon-theme (sub-step 2), removes
#              wallpaper + first-run script (sub-step 8), scrubs /etc/skel
#              (sub-step 12), and cleans per-user panel-2 + marker (sub-step 13).
# ==============================================================================

# ------------------------------------------------------------------------------
# Helper — run an X11 / xfconf command as the live oem user with the right
# DISPLAY / XAUTHORITY / DBUS_SESSION_BUS_ADDRESS so xfconfd can be reached.
# Without DBUS_SESSION_BUS_ADDRESS, xfconf-query writes silently nowhere.
# Returns the command's exit status; callers add `|| true` if they don't care.
# ------------------------------------------------------------------------------
oem_user_xrun() {
    local user="$1"; shift
    local home dbus_addr
    home=$(getent passwd "$user" | cut -d: -f6)

    # Find a running process owned by the user that has DBUS_SESSION_BUS_ADDRESS
    # set in its environment (xfsettingsd is reliable; fall back to any session).
    local pid
    pid=$(pgrep -u "$user" -x xfsettingsd 2>/dev/null | head -1 || true)
    [ -z "$pid" ] && pid=$(pgrep -u "$user" -x xfce4-session 2>/dev/null | head -1 || true)

    # Read the DBUS_SESSION_BUS_ADDRESS line from the target process' environ.
    # NOTE: the value itself can contain '=' (e.g. `unix:path=/tmp/dbus-XXXX`),
    # so we cannot split on '='; we just take everything after the first '='.
    if [ -n "$pid" ] && [ -r "/proc/$pid/environ" ]; then
        dbus_addr=$(tr '\0' '\n' < "/proc/$pid/environ" \
                    | awk '/^DBUS_SESSION_BUS_ADDRESS=/{ print substr($0, index($0,"=")+1); exit }' || true)
    fi

    # We deliberately route through `env` rather than passing inline
    # VAR=value to sudo: sudo's env_reset filters most VAR=value pairs
    # given on its command line unless they are in env_keep, which
    # makes DBUS_SESSION_BUS_ADDRESS unreliable. `sudo … env VAR=value
    # cmd` instead exec()s `env` with the post-sudo environment plus
    # our overrides, then `env` exec()s the target — guaranteed to
    # deliver every variable.
    #
    # HOME is the critical addition. Without it the child inherits
    # /root, which makes `~/.config` writes land under /root and (e.g.)
    # the oem-first-run marker end up in the wrong place — the buyer
    # would then see the first-run script re-run on their initial
    # login. PATH is set explicitly because `sudo`'s default secure_path
    # may not include /usr/local/bin (where oem-first-run.sh lives).
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
    echo "--> Installing visual theme and icon packages..."

    # Mint-Y-Aqua ships with mint-themes which is always installed on Mint.
    # We install the GTK2 engine that makes Mint-Y-Aqua render correctly on
    # GTK2 widgets (XFCE panel, older apps). Without it the theme is selected
    # but visually inert on those widgets.
    ensure_apt_fresh
    apt-get install -y papirus-icon-theme gtk2-engines-murrine
    echo "    [+] papirus-icon-theme installed."
    echo "    [+] gtk2-engines-murrine installed."

    # -------------------------------------------------------------------------
    # Wallpaper file deploy
    # -------------------------------------------------------------------------
    echo "--> Installing wallpaper..."
    mkdir -p /usr/share/backgrounds/oem-setup
    cp "$REPO_DIR/assets/wallpapers/malta.jpg" \
       /usr/share/backgrounds/oem-setup/malta.jpg
    echo "    [+] /usr/share/backgrounds/oem-setup/malta.jpg deployed."

    # -------------------------------------------------------------------------
    # First-run applier script — runs once per user account on first login.
    # Sets wallpaper, sets theme/icons, creates the bottom panel-2 dock, then
    # self-deletes its autostart entry so the user keeps full control.
    # -------------------------------------------------------------------------
    install -m 755 "$REPO_DIR/assets/scripts/oem-first-run.sh" \
                   /usr/local/bin/oem-first-run.sh
    echo "    [+] /usr/local/bin/oem-first-run.sh deployed."

    # -------------------------------------------------------------------------
    # Copy skel/ tree → /etc/skel so every new user account inherits:
    #   - GTK + icon theme defaults (xsettings.xml)
    #   - touchegg-client and oem-first-run autostart entries
    # -------------------------------------------------------------------------
    echo "--> Staging defaults into /etc/skel..."
    cp -r "$REPO_DIR/skel/." /etc/skel/

    # -------------------------------------------------------------------------
    # Mirror skel into the live oem user's home and apply everything live.
    #
    # /etc/skel is consulted by useradd ONLY when a new account is created.
    # The oem user pre-exists, so without this block the technician sees:
    #   - no wallpaper            (oem-first-run.sh autostart never copied)
    #   - no panel dock           (oem-first-run.sh never ran for this user)
    #   - theme has no effect     (xsettings.xml never copied; xfsettingsd
    #                              cached the old value; xfwm4 theme not set)
    # -------------------------------------------------------------------------
    if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null; then
        SUDO_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

        echo "--> Mirroring skel defaults into live user's home: $SUDO_USER"

        sudo -u "$SUDO_USER" mkdir -p \
            "$SUDO_HOME/.config/autostart" \
            "$SUDO_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"

        # Autostart entries for the live oem session.
        for f in oem-first-run.desktop touchegg-client.desktop; do
            if [ -f "/etc/skel/.config/autostart/$f" ]; then
                cp "/etc/skel/.config/autostart/$f" \
                   "$SUDO_HOME/.config/autostart/$f"
            fi
        done

        # xsettings — primary source-of-truth for GTK theme + icons.
        # Overwrite any pre-existing oem copy so our values win.
        if [ -f "/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" ]; then
            cp -f /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml \
                  "$SUDO_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"
        fi

        chown -R "$SUDO_USER:$SUDO_USER" \
            "$SUDO_HOME/.config/autostart" \
            "$SUDO_HOME/.config/xfce4"

        # Push the same values via xfconf-query so the running xfsettingsd
        # picks them up without waiting for a re-login. Also set the xfwm4
        # window-decoration theme — without this, only widget colours change
        # and the title bars stay default-grey.
        oem_user_xrun "$SUDO_USER" xfconf-query \
            -c xsettings -p /Net/ThemeName -s "Mint-Y-Aqua" 2>/dev/null || true
        oem_user_xrun "$SUDO_USER" xfconf-query \
            -c xsettings -p /Net/IconThemeName -s "Papirus" 2>/dev/null || true
        oem_user_xrun "$SUDO_USER" xfconf-query \
            -c xfwm4 -p /general/theme -s "Mint-Y-Aqua" 2>/dev/null || true

        # Force xfsettingsd to reload — `--replace` tells the existing
        # instance to quit and the new one to take over with fresh values.
        sudo -u "$SUDO_USER" pkill -x xfsettingsd 2>/dev/null || true
        sleep 0.3
        oem_user_xrun "$SUDO_USER" xfsettingsd --replace 2>/dev/null &
        disown 2>/dev/null || true

        # Run the per-user first-run script inline so the live session sees the
        # wallpaper and the bottom panel-2 dock immediately, without a re-login.
        # The marker file created at the end makes the autostart entry silently
        # no-op on all subsequent logins.
        oem_user_xrun "$SUDO_USER" /usr/local/bin/oem-first-run.sh 2>/dev/null || true

        echo "    [+] Theme, wallpaper, and dock panel applied to live session for user: $SUDO_USER"
    else
        echo "    [i] \$SUDO_USER not set — theme will apply on next login via skel."
    fi
}
