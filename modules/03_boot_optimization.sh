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
fi

if systemctl list-unit-files 2>/dev/null | grep -q '^NetworkManager-wait-online\.service'; then
    systemctl mask --now NetworkManager-wait-online.service 2>/dev/null || true
    echo "    [+] Masked NetworkManager-wait-online.service"
fi


# --- AMD EARLY KMS TTY SCREEN FIX ---
# Detect if the hardware is running an AMD CPU or GPU
if lspci 2>/dev/null | grep -iq "VGA.*AMD" || lscpu 2>/dev/null | grep -iq "AMD"; then
    echo "--> AMD Hardware Detected! Implementing Early Kernel Mode Setting (KMS) to fix TTY leak..."
    INITRAMFS_MODS="/etc/initramfs-tools/modules"
    
    if [ -f "$INITRAMFS_MODS" ]; then
        local_initramfs_changed=0
        for mod in amdgpu radeon; do
            if ! grep -qxF "$mod" "$INITRAMFS_MODS"; then
                echo "$mod" >> "$INITRAMFS_MODS"
                local_initramfs_changed=1
            fi
        done

        if [ "$local_initramfs_changed" -eq 1 ]; then
            echo "    [+] Injected graphics drivers into initramfs. Rebuilding boot images..."
            update-initramfs -u
            echo "    [+] Boot image optimization complete."
        else
            echo "    [i] AMD early driver loading already configured."
        fi
    fi
else
    echo "--> Intel/Other hardware detected. Skipping early KMS module additions."
fi
# ------------------------------------


if [ -f /etc/default/grub ]; then
    echo "--> Tuning GRUB parameters to permanently hide boot console tracking text…"
    
    TARGET_OPTS="quiet splash loglevel=3 rd.systemd.show_status=auto rd.udev.log_level=3 vt.global_cursor_default=0"
    
    # Check if GRUB is already configured perfectly
    if ! grep -q "GRUB_CMDLINE_LINUX_DEFAULT=\"$TARGET_OPTS\"" /etc/default/grub; then
        # Safely overwrite the line cleanly, protecting against duplicate logic strings
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="'"$TARGET_OPTS"'"/' /etc/etc/default/grub 2>/dev/null \
        || sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="'"$TARGET_OPTS"'"/' /etc/default/grub
        
        echo "    [+] Updated GRUB configurations with smooth boot switches."
        update-grub
        echo "    [+] update-grub completed successfully."
    else
        echo "    [i] GRUB options match targets exactly. No modification required."
    fi
else
    echo "    [!] /etc/default/grub not found — GRUB tweaks skipped."
fi

mark_done
echo "[${MODULE_ID}] Done. Re-run complete to register seamless splash profiles."