#!/bin/bash
# ==============================================================================
#   Module:    themes.sh
#   Purpose:   ChromeOS-like layout polish: Plank dock (bottom-centre) seeded
#              per-user by oem-first-run.sh, Malta wallpaper, and /etc/skel
#              staging (autostart). Does not override GTK/icon themes — distro
#              defaults apply (Xubuntu LTS compatible).
#   Reads:     REPO_DIR/assets/wallpapers/malta.jpg
#              REPO_DIR/assets/scripts/oem-first-run.sh
#              REPO_DIR/skel/...
#              SUDO_USER (optional, for live-session apply)
#              helpers: ensure_apt_fresh
#   Writes:    apt: plank
#              /usr/share/backgrounds/oem-setup/malta.jpg
#              /usr/local/bin/oem-first-run.sh       (mode 755)
#              /etc/skel/...                         (full skel tree copy)
#              ~SUDO_USER/.config/autostart          (mirrored from skel; same for
#              every human UID 1000–65533 without .oem-first-run-done)
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

# Seed oem-first-run.desktop into every interactive home that has not finished
# first-run yet. Without this, only $SUDO_USER (the account that ran sudo) and
# brand-new accounts (from /etc/skel at user creation time) would get the layout.
_oem_sync_oem_first_run_autostart_all_users() {
    local src="/etc/skel/.config/autostart/oem-first-run.desktop"
    [ -f "$src" ] || return 0

    oem_tty_say "--> Syncing oem-first-run autostart → homes without .oem-first-run-done…"

    local u uid home marker
    while IFS=: read -r u _ uid _ _ home _; do
        [ "$uid" -ge 1000 ] 2>/dev/null || continue
        [ "$uid" -lt 65534 ] 2>/dev/null || continue
        [ -n "${home:-}" ] && [ -d "$home" ] || continue
        marker="$home/.config/.oem-first-run-done"
        [ -f "$marker" ] && continue

        install -d -m 755 -o "$u" -g "$u" "$home/.config/autostart"
        install -m 644 -o "$u" -g "$u" "$src" "$home/.config/autostart/oem-first-run.desktop"
        oem_tty_say "    [+] oem-first-run autostart synced → ~$u (uid $uid)"
    done < /etc/passwd
}

step_themes() {
    oem_tty_say "--> Installing Plank (dock)…"

    ensure_apt_fresh
    oem_run_log env DEBIAN_FRONTEND=noninteractive apt-get install -y plank
    oem_tty_say "    [+] plank installed."

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

    _oem_sync_oem_first_run_autostart_all_users

    if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null; then

        oem_tty_say "--> Applying Plank + wallpaper in live session: $SUDO_USER"
        oem_user_xrun "$SUDO_USER" /usr/local/bin/oem-first-run.sh 2>/dev/null || true

        oem_tty_say "    [+] Wallpaper and Plank dock applied to live session for user: $SUDO_USER"
    else
        oem_tty_say "    [i] \$SUDO_USER not set — run themes from sudo on a graphical session" \
                     " or log each user out/in once so oem-first-run can apply."
    fi

    oem_tty_say "--> Validating dock configuration…"
    local expected_apps=(
        Netflix PrimeVideo DisneyPlus HBOMax Spotify YouTube
        Gmail GoogleDocs GoogleSheets GoogleSlides GoogleDrive Gemini ChromeRemoteDesktop
    )
    local dock_ok=0
    for app in "${expected_apps[@]}"; do
        [ -f "/usr/share/applications/${app}.desktop" ] && dock_ok=$((dock_ok + 1))
    done
    if [ "$dock_ok" -eq 13 ]; then
        oem_tty_say "    [+] All 13 web-app dock items present."
    elif [ "$dock_ok" -gt 0 ]; then
        oem_tty_say "    [!] Warning: only $dock_ok/13 web-app dock items found — verify they were installed correctly (menu option 8)."
    fi
}
