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

echo "--> Configuring boot sequence UX..."

if [ -f /etc/default/grub ]; then
    # Hardware Detection Branching
    if lspci 2>/dev/null | grep -iq "VGA.*AMD" || lscpu 2>/dev/null | grep -iq "AMD"; then
        echo "    [i] AMD Hardware Detected (Stoney Ridge CRAT Delay)."
        echo "    [+] Applying 'Diagnostic Boot' UX to mask the 30-second firmware timeout..."
        
        # Remove 'quiet' and 'splash' so the user sees the active systemd boot text
        # Remove the blinking cursor to keep it looking clean and intentional
        TARGET_OPTS="loglevel=3 rd.systemd.show_status=auto vt.global_cursor_default=0"
    else
        echo "    [i] Intel/Other Hardware Detected."
        echo "    [+] Applying standard silent Plymouth splash screen..."
        
        TARGET_OPTS="quiet splash loglevel=3 rd.systemd.show_status=auto vt.global_cursor_default=0"
    fi
    
    if ! grep -q "GRUB_CMDLINE_LINUX_DEFAULT=\"$TARGET_OPTS\"" /etc/default/grub; then
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="'"$TARGET_OPTS"'"/' /etc/default/grub
        
        echo "    [+] Updated GRUB configuration."
        update-grub
        echo "    [+] update-grub completed successfully."
    else
        echo "    [i] GRUB options already match targets. No modification required."
    fi
else
    echo "    [!] /etc/default/grub not found — GRUB tweaks skipped."
fi

mark_done
echo "[${MODULE_ID}] Done."