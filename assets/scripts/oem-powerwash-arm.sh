#!/bin/bash
# ==============================================================================
#   Script:       oem-powerwash-arm.sh
#   Purpose:      Tiny privileged helper. Drops the flag the boot-time
#                 finalize service watches for, enables the unit, and reboots.
#                 Does NOT perform the destructive wipe itself — that happens
#                 in oem-powerwash-finalize.sh on the next boot where no
#                 user sessions exist.
#   Installed to: /usr/local/sbin/oem-powerwash-arm.sh   (mode 700)
#   Installed by: modules/powerwash.sh
#   Runs as:      root, invoked via pkexec gated by the policy at
#                 /usr/share/polkit-1/actions/org.linuxoem.powerwash.policy
#                 (action id: org.linuxoem.powerwash.arm)
#   Reads:        PKEXEC_UID (optional, for the audit line in the flag file)
#   Writes:       /var/lib/oem-setup/powerwash.flag  (atomic via mktemp + mv)
#                 systemd: daemon-reload + enable oem-powerwash-finalize.service
#                 systemctl reboot   (~2 s after writing the flag)
#   Uninstall:    step_uninstall (sub-step 8b) removes this script.
#   Docs:         docs/powerwash.md (end-to-end flow)
#
#   NOTE: the flag file is the entire interface between user-space and the
#   boot-time service. Its existence triggers the wipe; its content (atime,
#   uid, name) is logged for audit but not otherwise consulted.
# ==============================================================================

set -Eeuo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "oem-powerwash-arm: must run as root (invoked via pkexec)." >&2
    exit 1
fi

STATE_DIR=/var/lib/oem-setup
FLAG="$STATE_DIR/powerwash.flag"
UNIT=oem-powerwash-finalize.service

mkdir -p "$STATE_DIR"

# Write atomically: a half-written flag would still trigger the finalize
# service (the service only checks for the file's existence), but a clean
# write keeps the log readable.
TMP="$(mktemp -p "$STATE_DIR" .powerwash.XXXXXX)"
# `|| true` on the lookup line: pkexec normally sets PKEXEC_UID, but if it
# ever isn't set (or refers to a deleted user) we still want to write the flag.
{
    echo "requested_at=$(date -Iseconds)"
    echo "requested_by_uid=${PKEXEC_UID:-unknown}"
    echo "requested_by_name=$(getent passwd "${PKEXEC_UID:-}" 2>/dev/null | cut -d: -f1 || true)"
} > "$TMP"
mv -f "$TMP" "$FLAG"
sync

systemctl daemon-reload    >/dev/null 2>&1 || true
systemctl enable "$UNIT"   >/dev/null 2>&1 || true

# Give the caller's "device will restart" zenity --info dialog a moment to
# render before we yank the rug.
sleep 2

systemctl reboot
