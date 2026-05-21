#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/var/lib/lubuntu-oem-setup}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/.state}"
MODULE_ID="14_keyd_after_login"

is_done() { [ -f "$STATE_FILE" ] && grep -qxF "$MODULE_ID" "$STATE_FILE"; }
mark_done() { mkdir -p "$STATE_DIR"; grep -qxF "$MODULE_ID" "$STATE_FILE" || echo "$MODULE_ID" >> "$STATE_FILE"; }

if is_done; then
    echo "[${MODULE_ID}] Already completed — skipping."
    exit 0
fi

if ! command -v keyd &>/dev/null || ! systemctl list-unit-files keyd.service &>/dev/null 2>&1; then
    echo "[${MODULE_ID}] keyd is not installed (run module 04 first) — skipping."
    exit 0
fi

echo "--> Configuring keyd for SDDM compatibility (Chromebook keyboard map after login)…"
echo "    [i] keyd at boot breaks the SDDM user list; start it in LXQt, stop it at logout."

systemctl disable keyd.service 2>/dev/null || true
systemctl stop keyd.service 2>/dev/null || true

echo "--> Allowing users to start keyd from the desktop session…"
cat > /etc/sudoers.d/oem-keyd-lxqt <<'EOF'
# Start Chromebook keyd only after graphical login (not at SDDM greeter).
Cmnd_Alias OEM_KEYD_CTL = /bin/systemctl start keyd.service, /bin/systemctl restart keyd.service
%users ALL=(root) NOPASSWD: OEM_KEYD_CTL
EOF
chmod 0440 /etc/sudoers.d/oem-keyd-lxqt
visudo -cf /etc/sudoers.d/oem-keyd-lxqt >/dev/null

mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/oem-keyd-stop.conf <<'EOF'
[General]
# Stop keyd when returning to the login screen so SDDM stays usable.
DisplayStopCommand=/usr/bin/systemctl stop keyd.service
EOF
echo "    [+] /etc/sddm.conf.d/oem-keyd-stop.conf"

mkdir -p /etc/skel/.config/autostart
cat > /etc/skel/.config/autostart/oem-keyd.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Chromebook keyboard (keyd)
Comment=Start keyd after login; SDDM runs without keyd
Exec=sh -c "systemctl is-active --quiet keyd.service 2>/dev/null || sudo -n systemctl start keyd.service"
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

systemctl restart sddm 2>/dev/null || true

mark_done
echo "[${MODULE_ID}] Done."
echo "    [i] Reboot or log out/in: SDDM should show users; keyd starts after LXQt login."
