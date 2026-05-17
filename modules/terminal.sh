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
# ==============================================================================

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
}
