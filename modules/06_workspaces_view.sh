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

echo "--> Installing system-wide XFCE keyboard shortcuts…"
mkdir -p /etc/xdg/xfce4/xfconf/xfce-perchannel-xml

KEYBIND_XML="/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml"

if [ ! -f "$KEYBIND_XML" ]; then
    cat > "$KEYBIND_XML" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-keyboard-shortcuts" version="1.0">
  <property name="commands" type="empty">
    <property name="custom" type="empty">
      <property name="Super_L" type="string" value="xfdashboard"/>
      <property name="F5" type="string" value="xfdashboard"/>
      <property name="XF86Scale" type="string" value="xfdashboard"/>
      <property name="XF86Explorer" type="string" value="xfdashboard"/>
    </property>
  </property>
</channel>
EOF
    echo "    [+] Created ${KEYBIND_XML}"
else
    changed=0
    for key in Super_L F5 XF86Scale XF86Explorer; do
        if ! grep -q "name=\"${key}\"" "$KEYBIND_XML" 2>/dev/null; then
            changed=1
        fi
    done
    if [ "$changed" -eq 1 ] || ! grep -q 'value="xfdashboard"' "$KEYBIND_XML" 2>/dev/null; then
        cat > "$KEYBIND_XML" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-keyboard-shortcuts" version="1.0">
  <property name="commands" type="empty">
    <property name="custom" type="empty">
      <property name="Super_L" type="string" value="xfdashboard"/>
      <property name="F5" type="string" value="xfdashboard"/>
      <property name="XF86Scale" type="string" value="xfdashboard"/>
      <property name="XF86Explorer" type="string" value="xfdashboard"/>
    </property>
  </property>
</channel>
EOF
        echo "    [+] Refreshed ${KEYBIND_XML} with xfdashboard bindings."
    else
        echo "    [i] xfdashboard shortcuts already present in ${KEYBIND_XML}."
    fi
fi

mark_done
echo "[${MODULE_ID}] Done."
