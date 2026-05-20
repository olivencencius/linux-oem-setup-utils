#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/var/lib/xubuntu-oem-setup}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/.state}"
MODULE_ID="05_touchpad_gestures"

is_done() { [ -f "$STATE_FILE" ] && grep -qxF "$MODULE_ID" "$STATE_FILE"; }
mark_done() { mkdir -p "$STATE_DIR"; grep -qxF "$MODULE_ID" "$STATE_FILE" || echo "$MODULE_ID" >> "$STATE_FILE"; }

if is_done; then
    echo "[${MODULE_ID}] Already completed — skipping."
    exit 0
fi

echo "--> Writing system-wide touchpad configuration (click-finger & natural scroll)…"
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/90-touchpad.conf <<'EOF'
Section "InputClass"
    Identifier      "oem-touchpad"
    MatchIsTouchpad "on"
    Driver          "libinput"
    Option "NaturalScrolling" "true"
    Option "Tapping"           "true"
    Option "ClickMethod"       "clickfinger"
EndSection
EOF
echo "    [+] /etc/X11/xorg.conf.d/90-touchpad.conf"

echo "--> Installing libinput-gestures dependencies…"
apt-get install -y libinput-tools xdotool wmctrl python3 make git

echo "--> Modifying /etc/adduser.conf so the final buyer inherits 'input' group permissions..."
# Enable extra groups for new users if commented out
sed -i 's/^#ADD_EXTRA_GROUPS=1/ADD_EXTRA_GROUPS=1/' /etc/adduser.conf || true
# Inject 'input' into the extra groups list if it isn't there already
if ! grep -q 'input' /etc/adduser.conf; then
    sed -i 's/^EXTRA_GROUPS="/EXTRA_GROUPS="input /' /etc/adduser.conf || true
fi

echo "--> Compiling and installing libinput-gestures globally…"
cd /tmp
rm -rf libinput-gestures
git clone --depth 1 https://github.com/bulletmark/libinput-gestures.git
cd libinput-gestures
make install

echo "--> Creating system-wide gesture mapping (3-finger swipe for workspaces)…"
# Note: ChromeOS swipes left to move the view right (next workspace)
cat > /etc/libinput-gestures.conf <<'EOF'
gesture swipe left 3 xdotool set_desktop --relative 1
gesture swipe right 3 xdotool set_desktop --relative -- -1
EOF
echo "    [+] /etc/libinput-gestures.conf"

echo "--> Setting libinput-gestures to autostart for the buyer…"
mkdir -p /etc/skel/.config/autostart
cat > /etc/skel/.config/autostart/libinput-gestures.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Libinput Gestures
Exec=libinput-gestures-setup start
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
echo "    [+] /etc/skel/.config/autostart/libinput-gestures.desktop"

# --- APPLY TO TECHNICIAN FOR QA ---
if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    TECH_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
    echo "--> Applying Touchpad/Gesture settings to technician user (${SUDO_USER}) for QA preview..."
    
    # 1. Add technician to the hardware input group
    usermod -aG input "${SUDO_USER}"
    
    # 2. Copy the autostart launcher
    mkdir -p "${TECH_HOME}/.config/autostart"
    cp /etc/skel/.config/autostart/libinput-gestures.desktop "${TECH_HOME}/.config/autostart/"
    chown "${SUDO_USER}:${SUDO_USER}" "${TECH_HOME}/.config/autostart/libinput-gestures.desktop"
    
    echo "    [+] Added ${SUDO_USER} to 'input' group and injected autostart."
fi
# ----------------------------------

mark_done
echo "[${MODULE_ID}] Done."
echo "⚠️  IMPORTANT FOR TECHNICIAN: Because you were just added to the 'input' group, you MUST log out and log back in (or reboot) before 3-finger swipes will work on your account."