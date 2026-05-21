#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/var/lib/lubuntu-oem-setup}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/.state}"
MODULE_ID="12_install_plank"

is_done() { [ -f "$STATE_FILE" ] && grep -qxF "$MODULE_ID" "$STATE_FILE"; }
mark_done() { mkdir -p "$STATE_DIR"; grep -qxF "$MODULE_ID" "$STATE_FILE" || echo "$MODULE_ID" >> "$STATE_FILE"; }

if is_done; then
    echo "[${MODULE_ID}] Already completed — skipping."
    exit 0
fi

echo "--> Moving Lubuntu native panel to the TOP..."
LXQT_SKEL_DIR="/etc/skel/.config/lxqt"
mkdir -p "$LXQT_SKEL_DIR"

# Fallback chain to find the true Lubuntu panel config
PANEL_SRC=""
for p in /etc/xdg/xdg-Lubuntu/lxqt/panel.conf /etc/xdg/lxqt/panel.conf /usr/share/lxqt/panel.conf; do
    if [ -f "$p" ]; then 
        PANEL_SRC="$p"
        break
    fi
done

if [ -n "$PANEL_SRC" ]; then
    cp "$PANEL_SRC" "${LXQT_SKEL_DIR}/panel.conf"
    sed -i -E 's/^position\s*=\s*Bottom/position=Top/i' "${LXQT_SKEL_DIR}/panel.conf"
    echo "    [+] Lubuntu panel position set to Top in skeleton (sourced from $PANEL_SRC)."
else
    echo "    [!] panel.conf not found in any standard LXQt directory. Skipping panel move."
fi

echo "--> Installing Plank dock…"
apt-get install -y plank

PLANK_SKEL="/etc/skel/.config/plank/dock1"
LAUNCHERS="${PLANK_SKEL}/launchers"
mkdir -p "$LAUNCHERS"

cat > "${PLANK_SKEL}/settings" <<'EOF'
[PlankDockPreferences]
CurrentWorkspaceOnly=false
IconSize=40
HideMode=2
Position=3
Offset=0
Theme=Gtk+
Alignment=3
LockItems=false
PinnedOnly=true
AutoPinning=false
EOF

resolve_desktop() {
    local candidates=("$@")
    local c
    for c in "${candidates[@]}"; do
        if [ -f "/usr/share/applications/${c}" ]; then
            echo "/usr/share/applications/${c}"
            return 0
        fi
    done
    return 1
}

write_dockitem() {
    local index="$1"
    shift
    local desktop path
    desktop=$(resolve_desktop "$@") || return 0
    path=$(printf '%03d' "$index")
    local base
    base=$(basename "$desktop" .desktop)
    cat > "${LAUNCHERS}/${path}-${base}.dockitem" <<EOF
[PlankDockItemPreferences]
Launcher=file://${desktop}
EOF
    echo "    [+] Dock item ${path}: $(basename "$desktop")"
}

rm -f "${LAUNCHERS}"/*.dockitem 2>/dev/null || true

idx=1
write_dockitem $((idx++)) pcmanfm-qt.desktop
write_dockitem $((idx++)) lxqt-config.desktop lxqt-config-center.desktop org.lxqt.lxqt-config.desktop
write_dockitem $((idx++)) org.kde.discover.desktop
write_dockitem $((idx++)) google-chrome.desktop
write_dockitem $((idx++)) webapp-googledocs.desktop
write_dockitem $((idx++)) webapp-googlesheets.desktop
write_dockitem $((idx++)) webapp-googleslides.desktop
write_dockitem $((idx++)) webapp-youtube.desktop
write_dockitem $((idx++)) webapp-netflix.desktop
write_dockitem $((idx++)) webapp-gmail.desktop
write_dockitem $((idx++)) webapp-gemini.desktop

mkdir -p /etc/skel/.config/autostart
cat > /etc/skel/.config/autostart/plank.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Plank
Comment=Dock
Exec=plank
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

# --- APPLY TO TECHNICIAN FOR QA ---
if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    TECH_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
    echo "--> Applying Plank & Panel configs to technician user (${SUDO_USER}) for QA preview..."
    
    mkdir -p "${TECH_HOME}/.config/autostart"
    
    # Cursor Catch: Explicitly create the LXQt config directory before attempting the copy
    mkdir -p "${TECH_HOME}/.config/lxqt"
    
    cp -r /etc/skel/.config/plank "${TECH_HOME}/.config/"
    cp /etc/skel/.config/autostart/plank.desktop "${TECH_HOME}/.config/autostart/"
    
    if [ -f "${LXQT_SKEL_DIR}/panel.conf" ]; then
        cp "${LXQT_SKEL_DIR}/panel.conf" "${TECH_HOME}/.config/lxqt/panel.conf"
    fi
    
    chown -R "${SUDO_USER}:${SUDO_USER}" "${TECH_HOME}/.config/plank"
    chown -R "${SUDO_USER}:${SUDO_USER}" "${TECH_HOME}/.config/lxqt"
    chown "${SUDO_USER}:${SUDO_USER}" "${TECH_HOME}/.config/autostart/plank.desktop"
    
    echo "    [+] Plank injected."
    echo "    [i] Restart your session to see the Panel move to the top."
fi
# ----------------------------------

mark_done
echo "[${MODULE_ID}] Done. New users inherit Plank from /etc/skel/."