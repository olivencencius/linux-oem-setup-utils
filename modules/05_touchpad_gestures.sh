#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/var/lib/lubuntu-oem-setup}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/.state}"
MODULE_ID="05_touchpad_gestures"

is_done() { [ -f "$STATE_FILE" ] && grep -qxF "$MODULE_ID" "$STATE_FILE"; }
mark_done() { mkdir -p "$STATE_DIR"; grep -qxF "$MODULE_ID" "$STATE_FILE" || echo "$MODULE_ID" >> "$STATE_FILE"; }

if is_done; then
    echo "[${MODULE_ID}] Already completed — refreshing gesture configs only."
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
apt-get install -y libinput-tools xdotool python3 make git

echo "--> Modifying /etc/adduser.conf so the final buyer inherits 'input' group permissions..."
sed -i 's/^#ADD_EXTRA_GROUPS=1/ADD_EXTRA_GROUPS=1/' /etc/adduser.conf || true
if ! grep -q 'input' /etc/adduser.conf; then
    sed -i 's/^EXTRA_GROUPS="/EXTRA_GROUPS="input /' /etc/adduser.conf || true
fi

echo "--> Compiling and installing libinput-gestures globally…"
if [ ! -f /usr/local/bin/libinput-gestures ]; then
    cd /tmp
    rm -rf libinput-gestures
    git clone --depth 1 https://github.com/bulletmark/libinput-gestures.git
    cd libinput-gestures
    make install
else
    echo "    [i] libinput-gestures binary already installed globally."
fi

echo "--> Creating system-wide ChromeOS gesture mapping…"
# FIX: Openbox handles Ctrl+Alt+Left/Right flawlessly for desktop switching.
# We also link "swipe up" directly to our skippy-xd overview client.
cat > /etc/libinput-gestures.conf <<'EOF'
gesture swipe left 3 xdotool key Ctrl+Alt+Right
gesture swipe right 3 xdotool key Ctrl+Alt+Left
gesture swipe up 3 skippy-xd --paging
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
    
    # 3. Live restart the gesture daemon for the technician if it's already running
    echo "--> Refreshing live gesture engine for technician QA..."
    sudo -u "${SUDO_USER}" libinput-gestures-setup restart 2>/dev/null || true
    
    echo "    [+] Added ${SUDO_USER} to 'input' group and synchronized configuration."
fi
# ----------------------------------

mark_done
echo "[${MODULE_ID}] Done."
echo "⚠️  CRITICAL FOR QA: If gestures still don't fire on your technician account, you MUST log out and log back in completely. Your user session cannot read trackpad data until the 'input' group membership initializes on a fresh login."