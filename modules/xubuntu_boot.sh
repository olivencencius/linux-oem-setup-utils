#!/bin/bash
# ==============================================================================
#   Module:    xubuntu_boot.sh
#   Purpose:   Optional machine-wide boot tweaks for Xubuntu / Ubuntu-family
#              resale images — NOT part of the default pipeline. Invoked only
#              from setup menu option 2.
#
#              Disables ModemManager and snapd, masks NetworkManager-wait-online,
#              appends silent-boot kernel params to GRUB_CMDLINE_LINUX_DEFAULT.
#              Does not mask systemd-udev-settle (try without first; measure with
#              systemd-analyze blame before masking manually).
#
#   Reads:     /etc/default/grub — helpers: backup_once
#   Writes:    systemd unit symlinks; /etc/default/grub + update-grub when changed
#   Step fn:   step_xubuntu_boot
#   Docs:      docs/modules/xubuntu_boot.md
#   Uninstall: step_uninstall restores units + strips GRUB tokens (fallback sed)
# ==============================================================================

step_xubuntu_boot() {
    echo "--> Xubuntu / Ubuntu-family boot optimisations (standalone, machine-wide)..."

    if systemctl list-unit-files 2>/dev/null | grep -q '^ModemManager\.service'; then
        systemctl disable --now ModemManager.service 2>/dev/null || true
        echo "    [+] Disabled ModemManager.service."
    else
        echo "    [i] ModemManager.service not installed — skipping."
    fi

    if systemctl list-unit-files 2>/dev/null | grep -q '^NetworkManager-wait-online\.service'; then
        systemctl mask --now NetworkManager-wait-online.service 2>/dev/null || true
        echo "    [+] Masked NetworkManager-wait-online.service."
    else
        echo "    [i] NetworkManager-wait-online.service not found — skipping."
    fi

    local snap_any=0
    if systemctl list-unit-files 2>/dev/null | grep -q '^snapd\.socket'; then
        systemctl disable --now snapd.socket 2>/dev/null || true
        snap_any=1
    fi
    if systemctl list-unit-files 2>/dev/null | grep -q '^snapd\.service'; then
        systemctl disable --now snapd.service 2>/dev/null || true
        snap_any=1
    fi
    if [ "$snap_any" = "1" ]; then
        echo "    [+] Disabled snapd.socket / snapd.service."
    else
        echo "    [i] snapd units not found — skipping."
    fi

    local grub_changed=0
    if [ ! -f /etc/default/grub ]; then
        echo "    [!] /etc/default/grub missing — GRUB tweaks skipped."
        echo ""
        echo "    [!] Reboot to apply systemd changes; GRUB was not modified."
        return 0
    fi

    local tok
    for tok in quiet splash loglevel=3 vt.global_cursor_default=0; do
        if grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | grep -Fq "$tok"; then
            continue
        fi
        backup_once /etc/default/grub
        sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/s/\"\$/ ${tok}\"/" /etc/default/grub
        grub_changed=1
    done

    if [ "$grub_changed" = "1" ]; then
        echo "    [+] Appended silent-boot kernel parameters to GRUB_CMDLINE_LINUX_DEFAULT."
        if command -v update-grub &>/dev/null; then
            update-grub
        else
            echo "    [!] update-grub not found — regenerate GRUB manually."
        fi
    else
        echo "    [i] Silent-boot GRUB parameters already present — leaving alone."
    fi

    echo ""
    echo "    [i] Reboot to apply GRUB and systemd boot behaviour."
    echo "    [i] Full uninstall (menu 15) reverses these changes."
}
