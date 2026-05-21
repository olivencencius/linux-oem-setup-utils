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

# Python script to safely inject XFCE shortcuts into any given XML file
inject_shortcuts() {
    local target_xml="$1"
    
    if [ ! -f "$target_xml" ]; then
        echo "    [i] Target XML not found at $target_xml, skipping."
        return
    fi

    python3 - << EOF
import xml.etree.ElementTree as ET
import os

xml_path = "$target_xml"
try:
    tree = ET.parse(xml_path)
    root = tree.getroot()
    
    custom_node = None
    for commands in root.findall(".//property[@name='commands']"):
        for custom in commands.findall("./property[@name='custom']"):
            custom_node = custom
            break
            
    if custom_node is not None:
        if 'type' in custom_node.attrib and custom_node.attrib['type'] == 'empty':
            del custom_node.attrib['type']
            
        # Added LaunchA and XF86LaunchA to catch your specific firmware output
        keys_to_bind = ["F5", "XF86Scale", "XF86Taskman", "XF86Display", "Super_L", "LaunchA", "XF86LaunchA"]
        existing_keys = {p.attrib.get('name') for p in custom_node.findall("./property")}
        
        for key in keys_to_bind:
            if key not in existing_keys:
                ET.SubElement(custom_node, "property", name=key, type="string", value="xfdashboard")
                
        tree.write(xml_path, encoding="UTF-8", xml_declaration=True)
        print(f"    [+] Successfully injected workspace shortcuts into {xml_path}")
except Exception as e:
    print(f"    [!] Error parsing {xml_path}: {e}")
EOF
}

echo "--> Configuring default shortcuts for all future users..."
mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/
SKEL_XML="/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml"

if [ ! -f "$SKEL_XML" ] && [ -f "/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml" ]; then
    cp "/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml" "$SKEL_XML"
fi
inject_shortcuts "$SKEL_XML"


# --- APPLY DIRECTLY TO TECHNICIAN PROFILE ---
if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    echo "--> Applying Workspaces shortcuts to technician user (${SUDO_USER})..."
    
    TECH_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
    TECH_XML="${TECH_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml"
    
    mkdir -p "${TECH_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/"
    if [ ! -f "$TECH_XML" ] && [ -f "/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml" ]; then
        cp "/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml" "$TECH_XML"
    fi
    
    inject_shortcuts "$TECH_XML"
    chown -R "${SUDO_USER}:${SUDO_USER}" "${TECH_HOME}/.config/"
    
    sudo -u "${SUDO_USER}" bash -c '
        if pgrep -x xfsettingsd > /dev/null; then
            xfsettingsd --replace &
        fi
    ' > /dev/null 2>&1
    echo "    [+] Keyboard shortcuts applied to live session."
fi
# ----------------------------------

mark_done
echo "[${MODULE_ID}] Done."