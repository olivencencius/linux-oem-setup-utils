#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/var/lib/lubuntu-oem-setup}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/.state}"
MODULE_ID="14_keyd_after_login"

GREETER_HELPER="/usr/local/sbin/oem-sddm-greeter-keyd-off.sh"

is_done() { [ -f "$STATE_FILE" ] && grep -qxF "$MODULE_ID" "$STATE_FILE"; }
mark_done() { mkdir -p "$STATE_DIR"; grep -qxF "$MODULE_ID" "$STATE_FILE" || echo "$MODULE_ID" >> "$STATE_FILE"; }

if is_done; then
    echo "[${MODULE_ID}] Already completed — re-applying SDDM/login fixes."
fi

has_keyd=false
if command -v keyd &>/dev/null && systemctl list-unit-files keyd.service &>/dev/null 2>&1; then
    has_keyd=true
fi

echo "--> Installing SDDM greeter helper (stop/mask keyd before login UI)…"
install -d /usr/local/sbin
cat > "$GREETER_HELPER" <<'EOF'
#!/bin/sh
# Keep SDDM usable on Chromebooks: keyd must not run on the greeter.
/usr/bin/systemctl stop keyd.service 2>/dev/null || true
/usr/bin/systemctl disable keyd.service 2>/dev/null || true
/usr/bin/systemctl mask keyd.service 2>/dev/null || true
exit 0
EOF
chmod 755 "$GREETER_HELPER"
echo "    [+] ${GREETER_HELPER}"

echo "--> Configuring SDDM (theme + scaling + keyd off at greeter)…"
apt-get install -y sddm-theme-breeze 2>/dev/null || true

mkdir -p /etc/sddm.conf.d
rm -f /etc/sddm.conf.d/oem-keyd-stop.conf 2>/dev/null || true
cat > /etc/sddm.conf.d/oem-login.conf <<EOF
[General]
DisplayStartCommand=${GREETER_HELPER}
DisplayStopCommand=${GREETER_HELPER}
GreeterEnvironment=QT_SCREEN_SCALE_FACTORS=1,QT_FONT_DPI=96

[Theme]
Current=breeze

[Users]
MinimumUid=1000
MaximumUid=60000
HideShell=false
EOF
echo "    [+] /etc/sddm.conf.d/oem-login.conf"

if [ "$has_keyd" = true ]; then
    echo "--> Disabling boot-time keyd (Chromebook map starts after LXQt login)…"
    systemctl stop keyd.service 2>/dev/null || true
    systemctl disable keyd.service 2>/dev/null || true
    systemctl mask keyd.service 2>/dev/null || true
    echo "    [i] keyd is-enabled: $(systemctl is-enabled keyd.service 2>&1 || echo unknown)"
    echo "    [i] keyd is-active:  $(systemctl is-active keyd.service 2>&1 || echo unknown)"

    cat > /etc/sudoers.d/oem-keyd-lxqt <<'EOF'
# Chromebook keyd: unmask+start after login only (greeter keeps it masked).
Cmnd_Alias OEM_KEYD_CTL = /bin/systemctl unmask keyd.service, /bin/systemctl start keyd.service, /bin/systemctl restart keyd.service
%users ALL=(root) NOPASSWD: OEM_KEYD_CTL
EOF
    chmod 0440 /etc/sudoers.d/oem-keyd-lxqt
    visudo -cf /etc/sudoers.d/oem-keyd-lxqt >/dev/null

    mkdir -p /etc/skel/.config/autostart
    cat > /etc/skel/.config/autostart/oem-keyd.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Chromebook keyboard (keyd)
Comment=Unmask and start keyd after login
Exec=sh -c "systemctl is-active --quiet keyd.service 2>/dev/null || sudo -n systemctl unmask keyd.service && sudo -n systemctl start keyd.service"
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
    echo "    [+] /etc/skel/.config/autostart/oem-keyd.desktop"

    if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
        TECH_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
        mkdir -p "${TECH_HOME}/.config/autostart"
        cp /etc/skel/.config/autostart/oem-keyd.desktop "${TECH_HOME}/.config/autostart/"
        chown "${SUDO_USER}:${SUDO_USER}" "${TECH_HOME}/.config/autostart/oem-keyd.desktop"
        echo "    [+] Autostart applied for technician (${SUDO_USER})."
    fi
else
    echo "    [i] keyd not installed — SDDM theme/scaling fix applied; run module 04 for keyboard map."
fi

# Run greeter prep now (helps before reboot if SDDM is restarted below).
"$GREETER_HELPER" || true

systemctl restart sddm 2>/dev/null || true

mark_done
echo "[${MODULE_ID}] Done."
echo "    [i] Reboot and check SDDM. If bootstrap menu 14 was skipped earlier, this script still updated the system."
echo "    [i] TTY check: systemctl is-enabled keyd  → should be masked or disabled."
