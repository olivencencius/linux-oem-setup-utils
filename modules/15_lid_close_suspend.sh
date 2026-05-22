#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/var/lib/lubuntu-oem-setup}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/.state}"
MODULE_ID="15_lid_close_suspend"

is_done() { [ -f "$STATE_FILE" ] && grep -qxF "$MODULE_ID" "$STATE_FILE"; }
mark_done() { mkdir -p "$STATE_DIR"; grep -qxF "$MODULE_ID" "$STATE_FILE" || echo "$MODULE_ID" >> "$STATE_FILE"; }

if is_done; then
    echo "[${MODULE_ID}] Already completed — refreshing power management configurations."
fi

echo "--> Optimizing lid-close suspend power states (deep sleep vs s2idle)…"

if [ -f /sys/power/mem_sleep ]; then
    if grep -q 's2idle' /sys/power/mem_sleep 2>/dev/null; then
        echo "--> Injecting systemd-tmpfiles deep-sleep override configuration..."
        mkdir -p /etc/tmpfiles.d
        echo "w /sys/power/mem_sleep - - - - deep" > /etc/tmpfiles.d/99-chromebook-deep-sleep.conf
        echo deep > /sys/power/mem_sleep || true
        echo "    [+] Forced hardware deep sleep (S3); persistent via native systemd-tmpfiles."
    else
        echo "    [i] mem_sleep has no s2idle option — using firmware default deep sleep."
    fi
fi

echo "--> Disabling hardware ACPI wakeups to prevent instant-wake loops..."
# /proc/acpi/wakeup toggles on write — only flip devices that are currently *enabled.
ACPI_WAKEUP_SCRIPT="/usr/local/sbin/oem-disable-acpi-wakeup.sh"
mkdir -p "$(dirname "$ACPI_WAKEUP_SCRIPT")"
cat > "$ACPI_WAKEUP_SCRIPT" <<'EOF'
#!/bin/bash
set -euo pipefail

WAKE_DEVICES=(XHC EHC GLAN WLAN TPAD TSCR)

for dev in "${WAKE_DEVICES[@]}"; do
    if grep -q "$dev" /proc/acpi/wakeup 2>/dev/null; then
        if grep "$dev" /proc/acpi/wakeup | grep -q "*enabled"; then
            echo "$dev" > /proc/acpi/wakeup || true
            echo "    [+] Disabled rogue wakeup trigger: $dev"
        fi
    fi
done
EOF
chmod 755 "$ACPI_WAKEUP_SCRIPT"
bash "$ACPI_WAKEUP_SCRIPT"

# Remove legacy tmpfiles rules that blindly toggled wake devices (could re-enable them).
rm -f /etc/tmpfiles.d/99-disable-acpi-wakeup.conf

echo "--> Installing boot-time ACPI wakeup guard (systemd oneshot)..."
cat > /etc/systemd/system/oem-disable-acpi-wakeup.service <<EOF
[Unit]
Description=Disable ACPI wake sources (OEM Chromebook)
DefaultDependencies=no
After=local-fs.target
Before=sleep.target suspend.target hibernate.target hybrid-sleep.target

[Service]
Type=oneshot
ExecStart=${ACPI_WAKEUP_SCRIPT}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl enable oem-disable-acpi-wakeup.service 2>/dev/null || true
echo "    [+] oem-disable-acpi-wakeup.service enabled."

echo "--> Installing suspend hook to block radios and re-apply ACPI wakeup guard..."
SLEEP_HOOK="/usr/lib/systemd/system-sleep/oem-suspend-power-guard"
mkdir -p "$(dirname "$SLEEP_HOOK")"
cat > "$SLEEP_HOOK" <<'EOF'
#!/bin/bash
set -euo pipefail

ACPI_WAKEUP_SCRIPT="/usr/local/sbin/oem-disable-acpi-wakeup.sh"

case "${1:-}/${2:-}" in
    pre/*)
        [ -x "$ACPI_WAKEUP_SCRIPT" ] && bash "$ACPI_WAKEUP_SCRIPT"
        if command -v rfkill &>/dev/null; then
            rfkill block wifi 2>/dev/null || true
            rfkill block bluetooth 2>/dev/null || true
        fi
        ;;
    post/*)
        if command -v rfkill &>/dev/null; then
            rfkill unblock wifi 2>/dev/null || true
            rfkill unblock bluetooth 2>/dev/null || true
        fi
        ;;
esac
EOF
chmod 755 "$SLEEP_HOOK"
echo "    [+] ${SLEEP_HOOK}"

# Drop invalid TLP keys from earlier revisions (not recognized by upstream TLP).
rm -f /etc/tlp.d/99-oem-suspend.conf

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
echo "    [+] systemd units reloaded."

mark_done
echo "[${MODULE_ID}] Done."
