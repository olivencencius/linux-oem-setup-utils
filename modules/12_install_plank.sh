#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/var/lib/xubuntu-oem-setup}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/.state}"
MODULE_ID="12_install_plank"

is_done() { [ -f "$STATE_FILE" ] && grep -qxF "$MODULE_ID" "$STATE_FILE"; }
mark_done() { mkdir -p "$STATE_DIR"; grep -qxF "$MODULE_ID" "$STATE_FILE" || echo "$MODULE_ID" >> "$STATE_FILE"; }

if is_done; then
    echo "[${MODULE_ID}] Already completed — skipping."
    exit 0
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

# Resolve .desktop paths (first match wins)
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
write_dockitem $((idx++)) thunar.desktop Thunar.desktop
write_dockitem $((idx++)) xfce4-settings-manager.desktop xfce-settings-manager.desktop
write_dockitem $((idx++)) google-chrome.desktop
write_dockitem $((idx++)) GoogleDocs.desktop
write_dockitem $((idx++)) GoogleSheets.desktop
write_dockitem $((idx++)) GoogleSlides.desktop
write_dockitem $((idx++)) YouTube.desktop
write_dockitem $((idx++)) Netflix.desktop
write_dockitem $((idx++)) Gmail.desktop
write_dockitem $((idx++)) Gemini.desktop

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

mark_done
echo "[${MODULE_ID}] Done. New users inherit Plank from /etc/skel/."
