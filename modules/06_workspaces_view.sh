#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/var/lib/lubuntu-oem-setup}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/.state}"
MODULE_ID="06_workspaces_view"

is_done() { [ -f "$STATE_FILE" ] && grep -qxF "$MODULE_ID" "$STATE_FILE"; }
mark_done() { mkdir -p "$STATE_DIR"; grep -qxF "$MODULE_ID" "$STATE_FILE" || echo "$MODULE_ID" >> "$STATE_FILE"; }

if is_done; then
    echo "[${MODULE_ID}] Already completed — skipping."
    exit 0
fi

echo "--> Installing skippy-xd (Lightweight macOS-style workspace overview)…"
apt-get install -y skippy-xd

echo "--> Configuring LXQt global hotkeys for Workspaces..."
LXQT_SKEL_DIR="/etc/skel/.config/lxqt"
GLOBAL_KEYS="${LXQT_SKEL_DIR}/globalkeyshortcuts.conf"

mkdir -p "$LXQT_SKEL_DIR"

if [ ! -f "$GLOBAL_KEYS" ]; then
    # Fallback chain to find the true Lubuntu defaults
    if [ -f /etc/xdg/xdg-Lubuntu/lxqt/globalkeyshortcuts.conf ]; then
        cp /etc/xdg/xdg-Lubuntu/lxqt/globalkeyshortcuts.conf "$GLOBAL_KEYS"
    elif [ -f /etc/xdg/lxqt/globalkeyshortcuts.conf ]; then
        cp /etc/xdg/lxqt/globalkeyshortcuts.conf "$GLOBAL_KEYS"
    elif [ -f /usr/share/lxqt/globalkeyshortcuts.conf ]; then
        cp /usr/share/lxqt/globalkeyshortcuts.conf "$GLOBAL_KEYS"
    else
        echo "    [!] Warning: Could not find default LXQt shortcuts. Generating a clean file."
        touch "$GLOBAL_KEYS"
    fi
fi

if ! grep -q 'skippy-xd' "$GLOBAL_KEYS" 2>/dev/null; then
    cat >> "$GLOBAL_KEYS" <<EOF

[F5.1]
Comment=Workspace Overview (F5)
Enabled=true
Exec=skippy-xd

[LaunchA.2]
Comment=Workspace Overview (Search Key)
Enabled=true
Exec=skippy-xd

[Super_L.3]
Comment=Workspace Overview (Super Key)
Enabled=true
Exec=skippy-xd

[XF86Scale.4]
Comment=Workspace Overview (Chromebook Overview Key 1)
Enabled=true
Exec=skippy-xd

[XF86Explorer.5]
Comment=Workspace Overview (Chromebook Overview Key 2)
Enabled=true
Exec=skippy-xd
EOF
    echo "    [+] Skippy-XD bindings injected into ${GLOBAL_KEYS}"
else
    echo "    [i] Skippy-XD bindings already present in ${GLOBAL_KEYS}"
fi

# --- APPLY TO TECHNICIAN FOR QA ---
if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    TECH_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
    echo "--> Applying Workspaces shortcuts to technician user (${SUDO_USER}) for QA preview..."
    
    mkdir -p "${TECH_HOME}/.config/lxqt"
    cp "$GLOBAL_KEYS" "${TECH_HOME}/.config/lxqt/globalkeyshortcuts.conf"
    chown -R "${SUDO_USER}:${SUDO_USER}" "${TECH_HOME}/.config/lxqt"
    
    echo "    [+] Keyboard shortcuts applied."
    echo "    [i] You may need to log out and log back in for LXQt to register the new hotkeys."
fi
# ----------------------------------

mark_done
echo "[${MODULE_ID}] Done."