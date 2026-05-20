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

echo "--> Writing system-wide touchpad configuration…"
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

echo "--> Installing touchegg and xdotool…"
apt-get install -y touchegg xdotool

mkdir -p /etc/touchegg
cat > /etc/touchegg/touchegg.conf <<'EOF'
<touchégg>
  <settings>
    <property name="animation_delay">150</property>
    <property name="action_execute_threshold">20</property>
    <property name="global_gestures">true</property>
  </settings>
  <application name="All">
    <gesture type="SWIPE" fingers="3" direction="LEFT">
      <action type="COMMAND">
        <command>xdotool set_desktop --relative -- -1</command>
      </action>
    </gesture>
    <gesture type="SWIPE" fingers="3" direction="RIGHT">
      <action type="COMMAND">
        <command>xdotool set_desktop --relative 1</command>
      </action>
    </gesture>
  </application>
</touchégg>
EOF
echo "    [+] /etc/touchegg/touchegg.conf (3-finger swipe = workspace prev/next via xdotool EWMH)"

systemctl enable touchegg.service 2>/dev/null || true
systemctl restart touchegg.service 2>/dev/null || true

mkdir -p /etc/skel/.config/autostart
if [ ! -f /etc/skel/.config/autostart/touchegg-client.desktop ]; then
    cat > /etc/skel/.config/autostart/touchegg-client.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Touchegg
Exec=touchegg
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
fi

mark_done
echo "[${MODULE_ID}] Done. Log out/in or reboot for touchpad + gestures."
