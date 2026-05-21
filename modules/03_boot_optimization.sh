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

echo "--> Restoring standard Plymouth loading spinner..."
if [ -f /etc/default/grub ]; then
    # Standard fast-boot parameters to ensure the Xubuntu spinner appears
    # Hides the blinking cursor for a cleaner look
    TARGET_OPTS="quiet splash loglevel=3 rd.systemd.show_status=auto vt.global_cursor_default=0"
    
    if ! grep -q "GRUB_CMDLINE_LINUX_DEFAULT=\"$TARGET_OPTS\"" /etc/default/grub; then
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="'"$TARGET_OPTS"'"/' /etc/default/grub
        
        echo "    [+] Updated GRUB configuration parameters."
        update-grub
        echo "    [+] update-grub completed successfully."
    else
        echo "    [i] GRUB options already match targets. No modification required."
    fi
else
    echo "    [!] /etc/default/grub not found — GRUB tweaks skipped."
fi

echo "--> Injecting multilingual 'Please wait' banner into TTY1..."
# Overwrite the default TTY greeting so the user doesn't see a scary system prompt 
# if the hardware delays the graphical interface.
cat > /etc/issue << 'EOF'


=============================================
  Please wait...
  Proszę czekać...
  Bitte warten...
  Veuillez patienter...
  Vänligen vänta...
=============================================


EOF
echo "    [+] /etc/issue banner updated."

mark_done
echo "[${MODULE_ID}] Done."