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
for svc in systemd-networkd-wait-online.service NetworkManager-wait-online.service; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}"; then
        systemctl mask --now "$svc" 2>/dev/null || true
        echo "    [+] Masked $svc"
    fi
done

echo "--> Tuning GRUB and system services based on hardware architecture…"

# Automatic Hardware Detection Branching
if lspci 2>/dev/null | grep -iq "VGA.*AMD" || lscpu 2>/dev/null | grep -iq "AMD"; then
    echo "    [i] AMD Hardware Detected. Applying Stoney APU specific optimizations..."
    
    echo "    [+] Disabling cellular modem scanning (ModemManager) to save 15+ seconds..."
    systemctl disable --now ModemManager.service 2>/dev/null || true
    systemctl mask ModemManager.service 2>/dev/null || true

    echo "    [+] Optimizing serial port tracking..."
    systemctl disable --now serial-getty@ttyS0.service 2>/dev/null || true

    # AMD specific GRUB parameters to bypass the firmware map conflict
    TARGET_OPTS="quiet splash loglevel=3 amd_iommu=off video=efifb:off"
else
    echo "    [i] Intel/Other Hardware Detected. Applying standard fast-boot optimizations..."
    
    # Standard fast-boot parameters that work perfectly on Intel ChromeOS hardware
    TARGET_OPTS="quiet splash loglevel=3 rd.systemd.show_status=auto vt.global_cursor_default=0"
fi

if [ -f /etc/default/grub ]; then
    if ! grep -q "GRUB_CMDLINE_LINUX_DEFAULT=\"$TARGET_OPTS\"" /etc/default/grub; then
        # Safely overwrite the line cleanly
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="'"$TARGET_OPTS"'"/' /etc/default/grub
        
        echo "    [+] Updated GRUB configuration parameters."
        update-grub
        echo "    [+] update-grub completed successfully."
    else
        echo "    [i] GRUB options already match targets exactly. No modification required."
    fi
else
    echo "    [!] /etc/default/grub not found — GRUB tweaks skipped."
fi

mark_done
echo "[${MODULE_ID}] Done."