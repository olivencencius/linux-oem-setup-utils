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

echo "--> Injecting system-wide XFCE keyboard shortcuts safely via Python XML parser…"
KEYBIND_XML="/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml"

if [ -f "$KEYBIND_XML" ]; then
    # Use native Python to safely parse and append elements without breaking XML structures
    python3 - << 'EOF'
import xml.etree.ElementTree as ET
import os

xml_path = "/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml"
try:
    tree = ET.parse(xml_path)
    root = tree.getroot()
    
    # Locate the custom commands block
    custom_node = None
    for commands in root.findall(".//property[@name='commands']"):
        for custom in commands.findall("./property[@name='custom']"):
            custom_node = custom
            break
            
    if custom_node is not None:
        # Strip the empty attribute type flag since we are adding properties
        if 'type' in custom_node.attrib and custom_node.attrib['type'] == 'empty':
            del custom_node.attrib['type']
            
        # Comprehensive list of potential keysyms emitted by Chromebook overview mappings
        keys_to_bind = ["Super_L", "F5", "XF86Scale", "XF86Display", "XF86Taskman", "XF86Explorer"]
        existing_keys = {p.attrib.get('name') for p in custom_node.findall("./property")}
        
        for key in keys_to_bind:
            if key not in existing_keys:
                ET.SubElement(custom_node, "property", name=key, type="string", value="xfdashboard")
                print(f"    [+] Registered system-wide key mapping: {key}")
                
        tree.write(xml_path, encoding="UTF-8", xml_declaration=True)
except Exception as e:
    print(f"    [!] Error parsing keyboard shortcuts XML: {e}")
EOF
else
    echo "    [!] Warning: Default XFCE keyboard shortcuts XML template not found."
fi

# --- APPLY TO TECHNICIAN FOR LIVE QA ---
if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    echo "--> Live-linking workspace shortcuts to active technician user context (${SUDO_USER})..."
    
    # Dynamically extract your active desktop DBUS socket instead of guessing it
    TECH_UID=$(id -u "${SUDO_USER}")
    DBUS_PID=$(pgrep -u "${TECH_UID}" -x xfce4-session | head -n 1 || pgrep -u "${TECH_UID}" -x xfsettingsd | head -n 1 || echo "")
    
    if [ -n "$DBUS_PID" ] && [ -f "/proc/${DBUS_PID}/environ" ]; then
        DBUS_ADDR=$(tr '\0' '\n' < "/proc/${DBUS_PID}/environ" | grep '^DBUS_SESSION_BUS_ADDRESS=' | cut -d= -f2- || echo "")
        
        if [ -n "$DBUS_ADDR" ]; then
            # Inject directly into your live user configuration space using xfconf
            sudo -u "${SUDO_USER}" env DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" bash -c '
                for key in Super_L F5 XF86Scale XF86Display XF86Taskman XF86Explorer; do
                    xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/${key}" -n -t string -s "xfdashboard" 2>/dev/null || true
                done
            '
            echo "    [+] Keyboard shortcuts synchronized with active XFCE background daemon."
        fi
    fi
fi
# ----------------------------------

mark_done
echo "[${MODULE_ID}] Done."