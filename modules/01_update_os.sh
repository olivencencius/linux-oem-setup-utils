#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/var/lib/lubuntu-oem-setup}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/.state}"
MODULE_ID="01_update_os"

is_done() { [ -f "$STATE_FILE" ] && grep -qxF "$MODULE_ID" "$STATE_FILE"; }
mark_done() { mkdir -p "$STATE_DIR"; grep -qxF "$MODULE_ID" "$STATE_FILE" || echo "$MODULE_ID" >> "$STATE_FILE"; }

if is_done; then
    echo "[${MODULE_ID}] Already completed — skipping."
    exit 0
fi

echo "--> Updating package lists…"
apt-get update

echo "--> Upgrading installed packages…"
apt-get upgrade -y

echo "--> Installing multimedia codecs and proprietary fonts silently…"
# 1. Pre-answer the Microsoft EULA agreement so the script doesn't hang
echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections

# 2. Install the restricted extras package
apt-get install -y ubuntu-restricted-extras

mark_done
echo "[${MODULE_ID}] Done."
