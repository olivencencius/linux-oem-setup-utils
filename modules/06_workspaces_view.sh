#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/var/lib/lubuntu-oem-setup}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/.state}"
MODULE_ID="06_workspaces_view"

is_done() { [ -f "$STATE_FILE" ] && grep -qxF "$MODULE_ID" "$STATE_FILE"; }
mark_done() { mkdir -p "$STATE_DIR"; grep -qxF "$MODULE_ID" "$STATE_FILE" || echo "$MODULE_ID" >> "$STATE_FILE"; }

# LXQt Exec is comma-separated (binary, arg1, …) — NOT a shell line. GUI saves:
#   Exec=/usr/bin/skippy-xd, --paging
# Shell-style "Exec=/usr/bin/skippy-xd --paging" runs the binary without --paging.
SKIPPY_EXEC="/usr/bin/skippy-xd, --paging"

# Lubuntu ships skippy shortcuts in /etc/xdg/... (often quoted, sometimes "-paging" typo).
SYSTEM_GLOBALKEYS=(
    /etc/xdg/xdg-Lubuntu/lxqt/globalkeyshortcuts.conf
    /etc/xdg/lxqt/globalkeyshortcuts.conf
    /usr/share/lxqt/globalkeyshortcuts.conf
)

normalize_skippy_exec() {
    local keys_file="$1"
    local tmp
    [ -f "$keys_file" ] || return 0
    if ! grep -q 'skippy-xd' "$keys_file" 2>/dev/null; then
        return 0
    fi
    # Do not use sed here: commas in "Exec=/usr/bin/skippy-xd, --paging" break sed substitutions.
    tmp="$(mktemp)"
    awk -v exec="$SKIPPY_EXEC" '
        { sub(/\r$/, "") }
        /^Exec=.*skippy-xd/ { print "Exec=" exec; next }
        { print }
    ' "$keys_file" > "$tmp"
    mv "$tmp" "$keys_file"
    echo "    [+] Fixed skippy Exec lines in ${keys_file}"
}

patch_all_lxqt_globalkeys() {
    local f
    for f in "${SYSTEM_GLOBALKEYS[@]}"; do
        normalize_skippy_exec "$f"
    done
}

ensure_skippy_hotkeys() {
    local keys_file="$1"

    mkdir -p "$(dirname "$keys_file")"
    if [ ! -f "$keys_file" ]; then
        for f in "${SYSTEM_GLOBALKEYS[@]}"; do
            if [ -f "$f" ]; then
                cp "$f" "$keys_file"
                echo "    [i] Created ${keys_file} from ${f}"
                break
            fi
        done
        [ -f "$keys_file" ] || touch "$keys_file"
    fi

    if grep -q '^\[LaunchA\.' "$keys_file" 2>/dev/null && ! grep -q '^\[XF86LaunchA\.' "$keys_file"; then
        sed -i 's/^\[LaunchA\./[XF86LaunchA./' "$keys_file"
        echo "    [+] Migrated LaunchA -> XF86LaunchA in ${keys_file}"
    fi

    if ! grep -q '^\[XF86LaunchA\.' "$keys_file" 2>/dev/null; then
        cat >> "$keys_file" <<EOF

[XF86LaunchA.1]
Comment=Workspace Overview (Chromebook Launcher Key)
Enabled=true
Exec=${SKIPPY_EXEC}
EOF
        echo "    [+] Added XF86LaunchA skippy binding to ${keys_file}"
    fi

    normalize_skippy_exec "$keys_file"
}

if is_done; then
    echo "[${MODULE_ID}] Already completed — refreshing workspace hotkeys only."
else

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

fi

echo "--> Fixing Lubuntu skippy shortcuts (system defaults + skel + user)…"
echo "    [i] Reboot does not re-run this script; shortcuts come from /etc/xdg and ~/.config."
patch_all_lxqt_globalkeys

LXQT_SKEL_DIR="/etc/skel/.config/lxqt"
GLOBAL_KEYS="${LXQT_SKEL_DIR}/globalkeyshortcuts.conf"
ensure_skippy_hotkeys "$GLOBAL_KEYS"

if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    TECH_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
    echo "--> Applying to technician (${SUDO_USER})…"
    mkdir -p "${TECH_HOME}/.config/lxqt" "${TECH_HOME}/.config/autostart"
    ensure_skippy_hotkeys "${TECH_HOME}/.config/lxqt/globalkeyshortcuts.conf"
    cp /etc/skel/.config/autostart/skippy-xd.desktop "${TECH_HOME}/.config/autostart/"
    chown -R "${SUDO_USER}:${SUDO_USER}" "${TECH_HOME}/.config/lxqt" "${TECH_HOME}/.config/autostart"
    if command -v lxqt-globalkeysd &>/dev/null && pgrep -u "${SUDO_USER}" -x lxqt-globalkeysd &>/dev/null; then
        sudo -u "${SUDO_USER}" killall -HUP lxqt-globalkeysd 2>/dev/null || true
    fi
    echo "    [+] Done. Log out/in if the launcher key still does nothing."
fi

mark_done
echo "[${MODULE_ID}] Done."
