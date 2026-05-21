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
if command -v skippy-xd &>/dev/null; then
    echo "    [i] skippy-xd already on PATH."
elif apt-cache show skippy-xd &>/dev/null 2>&1; then
    apt-get install -y skippy-xd
else
    echo "    [i] skippy-xd is not packaged for Lubuntu/Ubuntu 26.04; building from upstream…"
    apt-get install -y --no-install-recommends \
        build-essential pkg-config git \
        libx11-dev libxft-dev libxrender-dev libxcomposite-dev \
        libxdamage-dev libxfixes-dev libxext-dev libxinerama-dev \
        libpng-dev zlib1g-dev libjpeg-dev libgif-dev
    BUILD_DIR="/tmp/skippy-xd-build"
    rm -rf "$BUILD_DIR"
    git clone --depth 1 --branch v2026.05.24 \
        https://github.com/felixfung/skippy-xd.git "$BUILD_DIR"
    make -C "$BUILD_DIR" -j"$(nproc 2>/dev/null || echo 2)"
    mkdir -p /usr/share/man/man1
    make -C "$BUILD_DIR" install PREFIX=/usr
    rm -rf "$BUILD_DIR"
    echo "    [+] skippy-xd installed to /usr/bin/skippy-xd"
fi

echo "--> Enabling skippy-xd daemon at login (required for overview hotkeys)…"
mkdir -p /etc/skel/.config/autostart
cat > /etc/skel/.config/autostart/skippy-xd.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Skippy-XD
Exec=skippy-xd --start-daemon
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
echo "    [+] /etc/skel/.config/autostart/skippy-xd.desktop"

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
Exec=skippy-xd --paging

[LaunchA.2]
Comment=Workspace Overview (Search Key)
Enabled=true
Exec=skippy-xd --paging

[Super_L.3]
Comment=Workspace Overview (Super Key)
Enabled=true
Exec=skippy-xd --paging

[XF86Scale.4]
Comment=Workspace Overview (Chromebook Overview Key 1)
Enabled=true
Exec=skippy-xd --paging

[XF86Explorer.5]
Comment=Workspace Overview (Chromebook Overview Key 2)
Enabled=true
Exec=skippy-xd --paging
EOF
    echo "    [+] Skippy-XD bindings injected into ${GLOBAL_KEYS}"
else
    echo "    [i] Skippy-XD bindings already present in ${GLOBAL_KEYS}"
fi

# --- APPLY TO TECHNICIAN FOR QA ---
if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    TECH_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
    echo "--> Applying Workspaces shortcuts to technician user (${SUDO_USER}) for QA preview..."
    
    mkdir -p "${TECH_HOME}/.config/lxqt" "${TECH_HOME}/.config/autostart"
    cp "$GLOBAL_KEYS" "${TECH_HOME}/.config/lxqt/globalkeyshortcuts.conf"
    cp /etc/skel/.config/autostart/skippy-xd.desktop "${TECH_HOME}/.config/autostart/"
    chown -R "${SUDO_USER}:${SUDO_USER}" "${TECH_HOME}/.config/lxqt" "${TECH_HOME}/.config/autostart"
    
    echo "    [+] Keyboard shortcuts and skippy-xd autostart applied."
    echo "    [i] You may need to log out and log back in for LXQt to register the new hotkeys."
fi
# ----------------------------------

mark_done
echo "[${MODULE_ID}] Done."