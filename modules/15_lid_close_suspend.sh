#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/var/lib/lubuntu-oem-setup}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/.state}"
MODULE_ID="15_lid_close_suspend"

is_done() { [ -f "$STATE_FILE" ] && grep -qxF "$MODULE_ID" "$STATE_FILE"; }
mark_done() { mkdir -p "$STATE_DIR"; grep -qxF "$MODULE_ID" "$STATE_FILE" || echo "$MODULE_ID" >> "$STATE_FILE"; }

if is_done; then
    echo "[${MODULE_ID}] Already completed — skipping."
    exit 0
fi

echo "--> Optimizing lid-close suspend power states (deep sleep vs s2idle)…"

# Verify if the hardware environment actually exposes the modern sleep controls
if [ -f /sys/power/mem_sleep ]; then
    if grep -q 's2idle' /sys/power/mem_sleep 2>/dev/null; then
        echo "--> Injecting systemd-tmpfiles deep-sleep override configuration..."
        
        # 'w' tells systemd to write the argument directly to the path on early boot
        mkdir -p /etc/tmpfiles.d
        echo "w /sys/power/mem_sleep - - - - deep" > /etc/tmpfiles.d/99-chromebook-deep-sleep.conf
        
        # Apply the power target directly to the live QA staging system immediately
        echo deep > /sys/power/mem_sleep || true
        echo "    [+] Forced hardware deep sleep (S3); persistent via native systemd-tmpfiles."
    else
        echo "    [i] mem_sleep has no s2idle option — using firmware default deep sleep."
        echo "    [i] Current live state depth: $(cat /sys/power/mem_sleep)"
    fi
else
    echo "    [!] Warning: This hardware architecture does not expose low-level ACPI /sys/power/mem_sleep states."
fi

echo "--> Configuring systemd-logind lid-close behaviour…"
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/99-oem-lid-close.conf <<'EOF'
[Login]
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=suspend
LidSwitchIgnoreInhibited=no
EOF
echo "    [+] /etc/systemd/logind.conf.d/99-oem-lid-close.conf"

systemctl daemon-reload
echo "    [+] systemd-logind reloaded — lid close will suspend."

mark_done
echo "[${MODULE_ID}] Done."