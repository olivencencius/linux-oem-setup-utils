#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/var/lib/xubuntu-oem-setup}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/.state}"
MODULE_ID="03_boot_optimization"

is_done() { [ -f "$STATE_FILE" ] && grep -qxF "$MODULE_ID" "$STATE_FILE"; }
mark_done() { mkdir -p "$STATE_DIR"; grep -qxF "$MODULE_ID" "$STATE_FILE" || echo "$MODULE_ID" >> "$STATE_FILE"; }

if is_done; then
    echo "[${MODULE_ID}] Already completed — skipping."
    exit 0
fi

echo "--> Masking network wait-online services (prevents WiFi-less boot hangs)…"

if systemctl list-unit-files 2>/dev/null | grep -q '^systemd-networkd-wait-online\.service'; then
    systemctl mask --now systemd-networkd-wait-online.service 2>/dev/null || true
    echo "    [+] Masked systemd-networkd-wait-online.service"
else
    echo "    [i] systemd-networkd-wait-online.service not present — skipping."
fi

if systemctl list-unit-files 2>/dev/null | grep -q '^NetworkManager-wait-online\.service'; then
    systemctl mask --now NetworkManager-wait-online.service 2>/dev/null || true
    echo "    [+] Masked NetworkManager-wait-online.service"
else
    echo "    [i] NetworkManager-wait-online.service not present — skipping."
fi

if [ -f /etc/default/grub ]; then
    echo "--> Tuning GRUB for quiet boot (hide TTY spam)…"
    local_changed=0
    grub_line='quiet splash loglevel=3 rd.systemd.show_status=auto rd.udev.log_level=3'

    for tok in $grub_line; do
        if grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | grep -Fq "$tok"; then
            continue
        fi
        sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/s/\"\$/ ${tok}\"/" /etc/default/grub
        local_changed=1
    done

    if [ "$local_changed" -eq 1 ]; then
        echo "    [+] Appended silent-boot parameters to GRUB_CMDLINE_LINUX_DEFAULT."
        update-grub
        echo "    [+] update-grub completed."
    else
        echo "    [i] GRUB silent-boot parameters already present."
        if command -v update-grub &>/dev/null; then
            update-grub
        fi
    fi
else
    echo "    [!] /etc/default/grub not found — GRUB tweaks skipped."
fi

mark_done
echo "[${MODULE_ID}] Done. Reboot to apply boot changes."
