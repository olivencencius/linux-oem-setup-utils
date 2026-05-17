#!/bin/bash
# ==============================================================================
#   Module:    gestures.sh
#   Purpose:   ChromeOS-like multi-finger touchpad gestures via libinput-gestures
#              (maps swipes/pinches to xdotool, xfdashboard, wmctrl, Whisker),
#              ships rofi + oem-add-workspace.sh for first-run shortcuts,
#              plus xfdashboard workspace overview and oem-workspace-overview
#              launcher for Plank.
#   Reads:     REPO_DIR/assets/configs/libinput-gestures.conf
#              REPO_DIR/assets/configs/oem-workspace-overview.desktop
#              REPO_DIR/assets/scripts/oem-add-workspace.sh
#              SUDO_USER (optional, for live-session start)
#              helpers: ensure_apt_fresh, backup_once
#   Writes:    apt: wmctrl, xdotool, xfdashboard, rofi, libinput-tools, python3
#              git clone + libinput-gestures-setup install:
#                /usr/bin/libinput-gestures, /usr/bin/libinput-gestures-setup,
#                /usr/share/applications/libinput-gestures.desktop
#              /etc/libinput-gestures.conf (from assets)
#              /etc/xdg/autostart/libinput-gestures.desktop (all GUI users)
#              /etc/adduser.conf — last EXTRA_GROUPS="…" gains "input" (new users)
#              All human users uid 1000–65533: usermod -aG input
#              /usr/share/applications/oem-workspace-overview.desktop
#              /usr/local/bin/oem-add-workspace.sh  (increment xfwm4 workspace count)
#              systemd: nothing (per-session process)
#   Step fn:   step_gestures_and_workspaces
#   Uninstall: step_uninstall kills libinput-gestures, runs libinput-gestures-setup
#              uninstall, removes autostart + /etc/libinput-gestures.conf;
#              restores /etc/adduser.conf from backup when present;
#              apt purge rofi with other gesture packages; rm oem-add-workspace.sh.
#
#   NOTE: libinput-gestures requires membership in the "input" group so each
#   desktop user can read the touchpad via libinput. We add "input" to
#   EXTRA_GROUPS in /etc/adduser.conf (last line wins on Ubuntu) and attach
#   existing users. Reboot (or re-login) is required for group changes to apply.
#   See: https://github.com/bulletmark/libinput-gestures
# ==============================================================================

_LIBINPUT_GESTURES_GIT="${LIBINPUT_GESTURES_GIT_REF:-https://github.com/bulletmark/libinput-gestures.git}"
_LIBINPUT_GESTURES_DIR="/var/cache/oem-setup/libinput-gestures-src"

# Append "input" to the LAST EXTRA_GROUPS="..." line so new accounts get it.
_oem_extend_adduser_extra_groups_with_input() {
    local cf="/etc/adduser.conf"
    [ -f "$cf" ] || return 0
    local last
    last=$(grep '^EXTRA_GROUPS=' "$cf" 2>/dev/null | tail -1 || true)
    echo "${last:-}" | grep -qw input && return 0

    backup_once "$cf"
    local ln
    ln=$(grep -n '^EXTRA_GROUPS=' "$cf" | tail -1 | cut -d: -f1 || true)
    if [ -z "${ln:-}" ]; then
        printf '\n# OEM setup: libinput-gestures touchpad reads\nEXTRA_GROUPS="input"\n' >>"$cf"
        oem_tty_say "    [+] /etc/adduser.conf: appended EXTRA_GROUPS with input (minimal image)."
        return 0
    fi

    sed -i "${ln}{/^EXTRA_GROUPS=\"\"$/s//EXTRA_GROUPS=\"input\"/;\
/^EXTRA_GROUPS=\"[^\"]/s/\(^EXTRA_GROUPS=\"[^\"]*\)\(\"$\)/\1 input\2/;}" "$cf"
    oem_tty_say "    [+] /etc/adduser.conf (EXTRA_GROUPS) now includes \"input\" for new users."
}

# Attach input group to every normal login user (uids 1000–65533).
_oem_existing_users_attach_input_group() {
    local u uid
    while IFS=: read -r u _ uid _ _ _ _; do
        [ "$uid" -ge 1000 ] 2>/dev/null || continue
        [ "$uid" -lt 65534 ] 2>/dev/null || continue
        id -nG "$u" 2>/dev/null | tr ' ' '\n' | grep -qx input && continue
        oem_tty_say "    [.] Adding user $u (uid=$uid) to group input…"
        if ! usermod -a -G input "$u" 2>/dev/null; then
            oem_tty_say \
                "    [!] Could not add user \"$u\" to group input — add manually (sudo usermod -aG input \"$u\")."
        fi
    done < /etc/passwd

    if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null \
        && ! id -nG "$SUDO_USER" | tr ' ' '\n' | grep -qx input; then
        if usermod -a -G input "$SUDO_USER" 2>/dev/null; then
            oem_tty_say "    [+] sudo user $SUDO_USER added to group input."
        fi
    fi
}

_install_libinput_gestures_upstream() {
    [ -x /usr/bin/libinput-gestures ] && [ -x /usr/bin/libinput-gestures-setup ] \
        && return 0

    oem_tty_say "--> Fetching libinput-gestures (upstream)…" "    [.] $_LIBINPUT_GESTURES_GIT"
    mkdir -p "$(dirname "$_LIBINPUT_GESTURES_DIR")"
    rm -rf "$_LIBINPUT_GESTURES_DIR"
    oem_run_log git clone --depth 1 "$_LIBINPUT_GESTURES_GIT" "$_LIBINPUT_GESTURES_DIR"

    (
        cd "$_LIBINPUT_GESTURES_DIR" || exit 1
        chmod +x libinput-gestures libinput-gestures-setup || true
        oem_tty_say "--> Running libinput-gestures-setup install…"
        env DEBIAN_FRONTEND=noninteractive ./libinput-gestures-setup install </dev/null >&3 2>&3
    ) || return 1
}

step_gestures_and_workspaces() {
    # Do not resume past this step until libinput-gestures is installed: older
    # toolkits shipped Touchegg (different daemon) — their .done marker would
    # otherwise skip libinput migration on upgrade.
    if [ ! -x /usr/bin/libinput-gestures ]; then
        rm -f "${STATE_DIR:-/var/lib/oem-setup/state}/gestures_and_workspaces.done" \
              "${STATE_DIR:-/var/lib/oem-setup/state}/gestures.done" 2>/dev/null || true
    fi

    oem_tty_say "--> Installing touchpad gestures (libinput-gestures) and workspace overview (xfdashboard)…"

    ensure_apt_fresh
    oem_tty_say \
        "--> apt: installing Python 3, libinput-tools, wmctrl, xdotool, xfdashboard, rofi…"
    env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        python3 libinput-tools wmctrl xdotool xfdashboard rofi \
        git \
        </dev/null >&3 2>&3

    if ! _install_libinput_gestures_upstream; then
        oem_tty_say "    [!] libinput-gestures install failed (git/network?)."
        return 1
    fi

    # Remove legacy Touchegg (different stack from apt; often broken vs our XML profile).
    oem_tty_say "    [.] Removing legacy Touchegg (if installed)…"
    systemctl disable --now touchegg.service 2>/dev/null || true
    env DEBIAN_FRONTEND=noninteractive apt-get purge -y touchegg 2>/dev/null || true
    rm -rf /etc/touchegg

    install -m 644 "$REPO_DIR/assets/configs/libinput-gestures.conf" \
        /etc/libinput-gestures.conf
    oem_tty_say "    [+] /etc/libinput-gestures.conf (OEM binding profile)"

    if [ -f /usr/share/applications/libinput-gestures.desktop ]; then
        install -m 644 /usr/share/applications/libinput-gestures.desktop \
            /etc/xdg/autostart/libinput-gestures.desktop
        oem_tty_say "    [+] /etc/xdg/autostart/libinput-gestures.desktop (all GUI sessions)"
    else
        oem_tty_say \
            '    [!] /usr/share/applications/libinput-gestures.desktop missing after install.'
        return 1
    fi

    if command -v update-desktop-database &>/dev/null; then
        oem_run_log update-desktop-database /usr/share/applications 2>/dev/null || true
    fi

    _oem_extend_adduser_extra_groups_with_input
    _oem_existing_users_attach_input_group

    oem_tty_say \
        "" \
        "    [i] libinput-gestures requires group \"input\" for every desktop account." \
        "        Extra users inherit it from /etc/adduser.conf; reboot or full re-login activates it."

    install -m 644 "$REPO_DIR/assets/configs/oem-workspace-overview.desktop" \
        /usr/share/applications/oem-workspace-overview.desktop
    oem_tty_say "    [+] /usr/share/applications/oem-workspace-overview.desktop"

    install -m 755 "$REPO_DIR/assets/scripts/oem-add-workspace.sh" \
        /usr/local/bin/oem-add-workspace.sh
    oem_tty_say "    [+] /usr/local/bin/oem-add-workspace.sh"

    # Live OEM session — start helper so QA can validate before reboot when group is already OK.
    if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null; then
        local USER_HOME
        USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        if id -nG "$SUDO_USER" | tr ' ' '\n' | grep -qx input; then
            pkill -u "$SUDO_USER" -f '/usr/bin/libinput-gestures' 2>/dev/null || true
            sudo -u "$SUDO_USER" env \
                DISPLAY="${DISPLAY:-:0}" \
                XAUTHORITY="$USER_HOME/.Xauthority" \
                XDG_RUNTIME_DIR="/run/user/$(id -u "$SUDO_USER")" \
                /usr/bin/libinput-gestures \
                >/dev/null 2>&1 &
            oem_tty_say "    [+] libinput-gestures started for live user $SUDO_USER."
        else
            oem_tty_say \
                "    [i] \"$SUDO_USER\" not yet in group input (re-login)" \
                "        — gestures will apply after group membership refreshes."
        fi
    else
        oem_tty_say \
            '    [i] $SUDO_USER not set — gestures start next login (/etc/xdg/autostart/libinput-gestures.desktop).'
    fi

