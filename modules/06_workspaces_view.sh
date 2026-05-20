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

echo "--> Injecting system-wide XFCE keyboard shortcuts safely…"
KEYBIND_XML="/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml"

if [ -f "$KEYBIND_XML" ]; then
    # Idempotency check: only inject if xfdashboard isn't already there
    if ! grep -q 'value="xfdashboard"' "$KEYBIND_XML" 2>/dev/null; then
        # Find the <property name="custom" type="empty"> line and inject our keys right below it
        sed -i '/<property name="custom" type="empty">/a \
      <property name="Super_L" type="string" value="xfdashboard"/>\
      <property name="F5" type="string" value="xfdashboard"/>\
      <property name="XF86Scale" type="string" value="xfdashboard"/>\
      <property name="XF86Explorer" type="string" value="xfdashboard"/>' "$KEYBIND_XML"
        echo "    [+] Injected xfdashboard bindings into ${KEYBIND_XML}."
    else
        echo "    [i] xfdashboard shortcuts already present in ${KEYBIND_XML}."
    fi
else
    echo "    [!] Warning: Default XFCE keyboard shortcuts XML not found. Skipping to prevent breakage."
fi

mark_done
echo "[${MODULE_ID}] Done."