#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/var/lib/xubuntu-oem-setup}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/.state}"
MODULE_ID="08_install_chrome"

is_done() { [ -f "$STATE_FILE" ] && grep -qxF "$MODULE_ID" "$STATE_FILE"; }
mark_done() { mkdir -p "$STATE_DIR"; grep -qxF "$MODULE_ID" "$STATE_FILE" || echo "$MODULE_ID" >> "$STATE_FILE"; }

if is_done; then
    echo "[${MODULE_ID}] Already completed — skipping."
    exit 0
fi

if command -v google-chrome-stable &>/dev/null || dpkg -s google-chrome-stable &>/dev/null 2>&1; then
    echo "    [i] Google Chrome already installed."
    mark_done
    echo "[${MODULE_ID}] Done."
    exit 0
fi

DEB="/tmp/google-chrome-stable_current_amd64.deb"
echo "--> Downloading Google Chrome…"
wget -O "$DEB" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

echo "--> Installing Google Chrome…"
apt-get install -y "$DEB"

rm -f "$DEB"

mark_done
echo "[${MODULE_ID}] Done."
