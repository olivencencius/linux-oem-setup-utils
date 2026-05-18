#!/bin/bash
# ==============================================================================
#   Module:    terminal.sh
#   Purpose:   Disable bash bracketed-paste mode system-wide so multi-line
#              pastes don't produce 0~/1~ garbage at start/end.
#   Reads:     helpers: backup_once
#   Writes:    /etc/inputrc           (idempotent append)
#              /etc/skel/.inputrc     (idempotent append; created if absent)
#              /var/lib/oem-setup/backups/inputrc (if /etc/inputrc existed)
#   Step fn:   step_terminal
#   Docs:      docs/modules/terminal.md
#   Uninstall: step_uninstall restores /etc/inputrc from backup or sed-removes
#              the appended line (sub-step 10); same for /etc/skel/.inputrc,
#              with the skel file removed if empty after sed.
#
#   Per-user:  Existing accounts (not only $SUDO_USER) get ~/.inputrc line if missing,
#              so bracketed-paste fix applies before / after children are added.
# ==============================================================================

_oem_sync_inputrc_bracketed_paste_all_users() {
    local line='set enable-bracketed-paste off'
    local u uid home
    oem_tty_say "--> Ensuring bracketed-paste fix in ~/.inputrc for uid 1000–65533…"
    while IFS=: read -r u _ uid _ _ home _; do
        [ "$uid" -ge 1000 ] 2>/dev/null || continue
        [ "$uid" -lt 65534 ] 2>/dev/null || continue
        [ -n "${home:-}" ] && [ -d "$home" ] || continue
        if grep -qxF "$line" "$home/.inputrc" 2>/dev/null; then
            continue
        fi
        touch "$home/.inputrc" 2>/dev/null || continue
        echo "$line" >>"$home/.inputrc"
        chown "$u:$u" "$home/.inputrc" 2>/dev/null || true
        oem_tty_say "    [+] ~/.inputrc bracketed-paste line → ~$u"
    done < /etc/passwd
}

step_terminal() {
    oem_tty_say "--> Disabling bracketed paste mode in terminal (system-wide inputrc)…"

    # System-wide default (active right now for any user)
    if ! grep -qxF 'set enable-bracketed-paste off' /etc/inputrc; then
        backup_once /etc/inputrc
        echo "set enable-bracketed-paste off" >> /etc/inputrc
    fi

    # Skeleton for new user accounts (idempotent)
    mkdir -p /etc/skel
    if ! grep -qxF 'set enable-bracketed-paste off' /etc/skel/.inputrc 2>/dev/null; then
        echo "set enable-bracketed-paste off" >> /etc/skel/.inputrc
    fi

    _oem_sync_inputrc_bracketed_paste_all_users
}
