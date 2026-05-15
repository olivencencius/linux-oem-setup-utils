#!/bin/bash
# ==============================================================================
#   Script:       oem-powerwash-finalize.sh
#   Purpose:      Boot-time wipe. Deletes every regular user account and
#                 home directory, re-arms the OEM first-boot wizard via
#                 oem-config-prepare, disables the unit, removes the flag,
#                 and reboots once for a clean wizard start.
#   Installed to: /usr/local/sbin/oem-powerwash-finalize.sh   (mode 700)
#   Installed by: modules/powerwash.sh
#   Triggered by: /etc/systemd/system/oem-powerwash-finalize.service
#                 (After=local-fs.target, Before=display-manager.service,
#                  ConditionPathExists=/var/lib/oem-setup/powerwash.flag)
#   Runs as:      root, on the boot after a confirmed Powerwash. Runs BEFORE
#                 any display manager, so no user is logged in and homes can
#                 be removed cleanly.
#   Reads:        /var/lib/oem-setup/powerwash.flag (existence check + audit),
#                 /etc/passwd, /etc/group
#   Writes:       /var/log/oem-powerwash.log         (append)
#                 userdel -r -f for every uid in [1000, 65534)
#                 rm -rf $home as fallback if userdel -r couldn't
#                 groupdel for orphan groups
#                 rm -f /var/lib/AccountsService/users/*
#                 oem-config-prepare [--quiet]       (re-arm Mint wizard)
#                 systemctl disable + rm flag + systemctl reboot
#   Uninstall:    step_uninstall (sub-step 8b) removes this script.
#   Docs:         docs/powerwash.md (end-to-end flow)
#
#   NOTE: the uid range [1000, 65534) deliberately includes the temporary
#   'oem' account if it somehow still exists on a re-flipped device —
#   oem-config-prepare will replace it cleanly anyway.
# ==============================================================================

set -u

FLAG=/var/lib/oem-setup/powerwash.flag
LOG=/var/log/oem-powerwash.log

# Nothing to do if the flag isn't there — service is also Condition'd on it,
# but defend-in-depth.
[ -f "$FLAG" ] || exit 0

exec >>"$LOG" 2>&1
echo ""
echo "================================================================="
echo "[$(date -Iseconds)] oem-powerwash-finalize starting"
echo "================================================================="

# ------------------------------------------------------------------------------
# 1. Wipe every buyer account.
#
#    Range: uid >= 1000 and < 65534 (nobody). The temporary 'oem' account
#    that ships with Mint OEM installs sits in this range too, but it has
#    been deleted by the time the toolkit reaches its first buyer; if it
#    somehow still exists, oem-config-prepare will replace it cleanly, so
#    we delete it like any other.
# ------------------------------------------------------------------------------
echo "--> Removing user accounts and home directories..."
while IFS=: read -r name _ uid _ _ home _; do
    [ "$uid" -ge 1000 ] && [ "$uid" -lt 65534 ] || continue

    echo "    [-] $name (uid=$uid, home=$home)"
    pkill -KILL -u "$name" 2>/dev/null || true
    sleep 1

    if ! userdel -r -f "$name" 2>/dev/null; then
        # Fallback if userdel -r couldn't remove the home (busy mount, etc.).
        userdel -f "$name" 2>/dev/null || true
        [ -n "$home" ] && [ "$home" != "/" ] && [ -d "$home" ] && rm -rf "$home"
    fi
done < /etc/passwd

# Drop matching group entries that userdel might have left behind because
# they had no members.
echo "--> Removing orphaned groups..."
while IFS=: read -r gname _ gid _; do
    [ "$gid" -ge 1000 ] && [ "$gid" -lt 65534 ] || continue
    if ! getent passwd | awk -F: -v g="$gname" '$1==g {found=1} END{exit !found}'; then
        groupdel "$gname" 2>/dev/null || true
    fi
done < /etc/group

# ------------------------------------------------------------------------------
# 2. Re-arm the OEM first-boot wizard.
#
#    Try the --quiet flag first; on older versions of oem-config that don't
#    support it, retry without the flag. If the binary is missing entirely,
#    fall back to a plain login.
# ------------------------------------------------------------------------------
echo "--> Re-arming OEM first-boot wizard..."
if command -v oem-config-prepare >/dev/null 2>&1; then
    if oem-config-prepare --quiet 2>&1; then
        echo "    [+] oem-config-prepare --quiet succeeded."
    elif oem-config-prepare 2>&1; then
        echo "    [+] oem-config-prepare (without --quiet) succeeded."
    else
        echo "    [!] oem-config-prepare returned non-zero — wizard may not auto-launch."
    fi
else
    echo "    [!] oem-config-prepare not installed."
    echo "        Device will boot to the login screen instead of the welcome wizard."
fi

# Clear any toolkit-staged per-user marker that lived outside the homes we
# just deleted.
rm -f /var/lib/AccountsService/users/* 2>/dev/null || true

# ------------------------------------------------------------------------------
# 3. Self-disable, clear flag, reboot once for a clean wizard start.
# ------------------------------------------------------------------------------
echo "--> Disabling oem-powerwash-finalize.service..."
systemctl disable oem-powerwash-finalize.service 2>/dev/null || true
rm -f "$FLAG"

sync
echo "[$(date -Iseconds)] oem-powerwash-finalize complete — rebooting."
systemctl reboot
