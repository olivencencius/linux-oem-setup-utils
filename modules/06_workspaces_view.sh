#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/var/lib/xubuntu-oem-setup}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/.state}"
MODULE_ID="06_workspaces_view"

is_done() { [ -f "$STATE_FILE" ] && grep -qxF "$MODULE_ID" "$STATE_FILE"; }
mark_done() { mkdir -p "$STATE_DIR"; grep -qxF "$MODULE_ID" "$STATE_FILE" || echo "$MODULE_ID" >> "$STATE_FILE"; }

if is_done; then
    echo "[${MODULE_ID}] Already completed — skipping."
    exit 0
fi

echo "--> Installing xfdashboard (ChromeOS-style workspace overview)…"
apt-get install -y xfdashboard

echo "--> Injecting system-wide XFCE keyboard shortcuts…"
KEYBIND_XML="/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml"

if [ -f "$KEYBIND_XML" ]; then
    if ! grep -q 'value="xfdashboard"' "$KEYBIND_XML" 2>/dev/null; then
        # Fixed your sed command to match <property name="custom"> even if type="empty" is missing
        sed -i '/<property name="custom".*>/a \
      <property name="LaunchA" type="string" value="xfdashboard"/>\
      <property name="Super_L" type="string" value="xfdashboard"/>\
      <property name="F5" type="string" value="xfdashboard"/>\
      <property name="XF86Scale" type="string" value="xfdashboard"/>\
      <property name="XF86Explorer" type="string" value="xfdashboard"/>' "$KEYBIND_XML"
        echo "    [+] Injected xfdashboard bindings into ${KEYBIND_XML}."
    else
        echo "    [i] xfdashboard shortcuts already present in ${KEYBIND_XML}."
    fi
else
    echo "    [!] Warning: Default XFCE keyboard shortcuts XML not found. Skipping."
fi

# --- APPLY TO TECHNICIAN FOR QA USING YOUR ORIGINAL DBUS LOGIC ---
if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    echo "--> Applying Workspaces shortcuts to technician user (${SUDO_USER}) for QA preview..."
    
    sudo -u "${SUDO_USER}" bash -c '
        export DISPLAY=:0
        export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
        
        # We talk directly to the daemon via DBUS just like you originally wrote
        xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/LaunchA" -n -t string -s "xfdashboard" 2>/dev/null || true
        xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/Super_L" -n -t string -s "xfdashboard" 2>/dev/null || true
        xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/F5" -n -t string -s "xfdashboard" 2>/dev/null || true
        xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/XF86Scale" -n -t string -s "xfdashboard" 2>/dev/null || true
        xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/XF86Explorer" -n -t string -s "xfdashboard" 2>/dev/null || true
    '
    echo "    [+] Keyboard shortcuts applied to live DBUS session."
fi
# ----------------------------------

mark_done
echo "[${MODULE_ID}] Done."