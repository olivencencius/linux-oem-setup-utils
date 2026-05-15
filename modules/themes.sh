#!/bin/bash
# ==============================================================================
#   Module:    themes.sh
#   Purpose:   The big one — ChromeOS GTK theme, Tela-blue icons, Plank dock
#              with a pinned ordered launcher list, Malta wallpaper, per-user
#              first-run script, and the entire /etc/skel staging.
#   Reads:     REPO_DIR/assets/wallpapers/malta.jpg
#              REPO_DIR/assets/scripts/oem-first-run.sh
#              REPO_DIR/skel/...
#              network: github.com/vinceliuice/ChromeOS-theme,Tela-icon-theme
#              SUDO_USER (optional, for live-session apply)
#              helpers: backup_once, ensure_apt_fresh
#   Writes:    apt: plank
#              /usr/share/themes/ChromeOS*
#              /usr/share/icons/Tela-blue*           (ONLY 'blue' variant)
#              /etc/dconf/profile/user               (idempotent append)
#              /etc/dconf/db/local.d/00-plank        (dock items + theme)
#              /etc/dconf/db/local                   (via dconf update)
#              /usr/share/backgrounds/oem-setup/malta.jpg
#              /usr/local/bin/oem-first-run.sh       (mode 755)
#              /etc/skel/...                         (full skel tree copy)
#              /var/lib/oem-setup/backups/user       (dconf profile, if existed)
#   Step fn:   step_themes
#   Helpers:   oem_user_xrun (file-scope)
#   Docs:      docs/modules/themes.md
#   Uninstall: step_uninstall reverse-installs the themes via upstream -r flag
#              (sub-step 4), purges plank (sub-step 2), removes dconf override
#              + profile additions + wallpaper + first-run script (sub-step 8),
#              and scrubs /etc/skel (sub-step 12) and per-user homes
#              (sub-step 13).
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

    sudo -u "$user" \
        DISPLAY="${DISPLAY:-:0}" \
        XAUTHORITY="$home/.Xauthority" \
        DBUS_SESSION_BUS_ADDRESS="${dbus_addr:-}" \
        "$@"
}

step_themes() {
    echo "--> Installing ChromeOS visual themes..."
    cd /tmp
    rm -rf ChromeOS-theme Tela-icon-theme

    # ChromeOS GTK theme (system-wide install when running as root).
    #
    # Upstream's install.sh ends each variant with:
    #     ln -sf "$THEME_DIR/gtk-4.0/assets" "$HOME/.config/gtk-4.0/assets"
    # with no `mkdir -p` before it. Under sudo, $HOME is /root, and /root has
    # no .config/gtk-4.0 on a fresh Mint install, so `ln` aborts with
    # "no such file or directory" and the whole step fails. Pre-create it.
    #
    # We also pin to `--color standard --size standard` (the 'ChromeOS' variant,
    # no suffix) because that's the only variant our xsettings.xml and
    # oem-first-run.sh ever select. The default would install 6 variants
    # (~50 MB) and, worse, the libadwaita link would end up pointing to
    # whichever variant is iterated last (ChromeOS-Light-Compact) instead of
    # our ChromeOS target.
    mkdir -p /root/.config/gtk-4.0
    git clone --depth 1 https://github.com/vinceliuice/ChromeOS-theme.git
    ./ChromeOS-theme/install.sh --color standard --size standard

    # Make every new user inherit GTK4 / libadwaita theming. Upstream only
    # links into the *invoking* user's $HOME (here: root), so without this
    # block buyers' GNOME apps would render with the default purple Adwaita
    # instead of the ChromeOS theme.
    mkdir -p /etc/skel/.config/gtk-4.0
    ln -sf /usr/share/themes/ChromeOS/gtk-4.0/assets   /etc/skel/.config/gtk-4.0/assets
    ln -sf /usr/share/themes/ChromeOS/gtk-4.0/gtk.css  /etc/skel/.config/gtk-4.0/gtk.css
    ln -sf /usr/share/themes/ChromeOS/gtk-4.0/gtk-dark.css \
                                                       /etc/skel/.config/gtk-4.0/gtk-dark.css

    # Same link inside the live oem session so libadwaita apps look right
    # without waiting for the buyer's first login.
    if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null; then
        SUDO_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        sudo -u "$SUDO_USER" mkdir -p "$SUDO_HOME/.config/gtk-4.0"
        sudo -u "$SUDO_USER" ln -sf /usr/share/themes/ChromeOS/gtk-4.0/assets \
                                    "$SUDO_HOME/.config/gtk-4.0/assets"
        sudo -u "$SUDO_USER" ln -sf /usr/share/themes/ChromeOS/gtk-4.0/gtk.css \
                                    "$SUDO_HOME/.config/gtk-4.0/gtk.css"
        sudo -u "$SUDO_USER" ln -sf /usr/share/themes/ChromeOS/gtk-4.0/gtk-dark.css \
                                    "$SUDO_HOME/.config/gtk-4.0/gtk-dark.css"
    fi

    # Tela icon theme — ONLY install the 'blue' variant (matches xsettings.xml
    # default below). Installing -a pulls ~100 MB of unused colour variants.
    git clone --depth 1 https://github.com/vinceliuice/Tela-icon-theme.git
    ./Tela-icon-theme/install.sh blue

    rm -rf /tmp/ChromeOS-theme /tmp/Tela-icon-theme

    # -------------------------------------------------------------------------
    # Plank dock
    # -------------------------------------------------------------------------
    echo "--> Installing Plank dock..."
    ensure_apt_fresh
    apt-get install -y plank

    # Plank autostart is staged via skel/.config/autostart/plank.desktop so it
    # starts per-user. We do NOT also drop /etc/xdg/autostart/plank.desktop —
    # the system-wide entry was duplicating the skel one and causing harmless
    # but ugly D-Bus warnings.

    # -------------------------------------------------------------------------
    # dconf system database — sets dock appearance AND the ordered list of
    # launchers for all users. Without dock-items, Plank's choice of which
    # .dockitem files to show is alphabetical / version-dependent.
    # -------------------------------------------------------------------------
    mkdir -p /etc/dconf/profile
    backup_once /etc/dconf/profile/user
    if [ -f /etc/dconf/profile/user ]; then
        grep -qxF 'user-db:user'    /etc/dconf/profile/user \
            || echo 'user-db:user'    >> /etc/dconf/profile/user
        grep -qxF 'system-db:local' /etc/dconf/profile/user \
            || echo 'system-db:local' >> /etc/dconf/profile/user
    else
        printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
    fi

    mkdir -p /etc/dconf/db/local.d
    cat > /etc/dconf/db/local.d/00-plank << 'EOF'
[net/launchpad/plank/docks/dock1]
theme='Transparent'
position='bottom'
icon-size=48
hide-mode='none'
dock-items=['google-chrome.dockitem', 'xfce4-settings-manager.dockitem', 'thunar.dockitem', 'vlc.dockitem', 'zoom.dockitem', 'gmail.dockitem', 'googledocs.dockitem', 'googledrive.dockitem', 'gemini.dockitem', 'youtube.dockitem', 'spotify.dockitem']
EOF
    dconf update

    # -------------------------------------------------------------------------
    # Wallpaper file deploy
    # -------------------------------------------------------------------------
    echo "--> Installing wallpaper..."
    mkdir -p /usr/share/backgrounds/oem-setup
    cp "$REPO_DIR/assets/wallpapers/malta.jpg" \
       /usr/share/backgrounds/oem-setup/malta.jpg

    # -------------------------------------------------------------------------
    # First-run applier script — runs once per user account on first login,
    # applies theme + wallpaper to detected monitors, then self-deletes.
    # -------------------------------------------------------------------------
    install -m 755 "$REPO_DIR/assets/scripts/oem-first-run.sh" \
                   /usr/local/bin/oem-first-run.sh
    echo "    [+] /usr/local/bin/oem-first-run.sh deployed."

    # -------------------------------------------------------------------------
    # Copy skel/ tree → /etc/skel so every new user account inherits:
    #   - GTK + icon theme defaults (xsettings.xml)
    #   - First-run autostart entry
    #   - Pre-pinned Plank launchers
    #   - Plank + imwheel autostart entries
    #   - imwheel scroll config (~/.imwheelrc)
    # -------------------------------------------------------------------------
    echo "--> Staging defaults into /etc/skel..."
    cp -r "$REPO_DIR/skel/." /etc/skel/

    # -------------------------------------------------------------------------
    # Apply theme immediately in the live (oem) X session for QA visibility
    # -------------------------------------------------------------------------
    if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null; then
        oem_user_xrun "$SUDO_USER" xfconf-query -c xsettings -p /Net/ThemeName -s "ChromeOS" \
            2>/dev/null || true
        oem_user_xrun "$SUDO_USER" xfconf-query -c xsettings -p /Net/IconThemeName -s "Tela-blue" \
            2>/dev/null || true
        echo "    [+] Theme applied to live session for user: $SUDO_USER"
    else
        echo "    [i] \$SUDO_USER not set — theme will apply on next login via skel."
    fi
}
