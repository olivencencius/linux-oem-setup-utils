#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/var/lib/xubuntu-oem-setup}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/.state}"
MODULE_ID="04_chromebook_fixes"

is_done() { [ -f "$STATE_FILE" ] && grep -qxF "$MODULE_ID" "$STATE_FILE"; }
mark_done() { mkdir -p "$STATE_DIR"; grep -qxF "$MODULE_ID" "$STATE_FILE" || echo "$MODULE_ID" >> "$STATE_FILE"; }

if is_done; then
    echo "[${MODULE_ID}] Already completed — skipping."
    exit 0
fi

if ! command -v git &>/dev/null; then
    echo "--> git not found — installing…"
    apt-get update
    apt-get install -y git
fi

echo "========================================="
echo "  Chromebook audio installer (interactive)"
echo "  Answer prompts on THIS terminal."
echo "========================================="
exec < /dev/tty

cd /tmp
rm -rf /tmp/chromebook-linux-audio
git clone --depth 1 --progress https://github.com/WeirdTreeThing/chromebook-linux-audio.git
cd /tmp/chromebook-linux-audio
if [ -x ./setup-audio ]; then
    ./setup-audio
elif [ -x ./setup.sh ]; then
    ./setup.sh
else
    echo "[!] No setup script found in chromebook-linux-audio repo." >&2
    exit 1
fi

echo ""
echo "========================================="
echo "  Chromebook keyboard map (interactive)"
echo "========================================="
exec < /dev/tty

cd /tmp
rm -rf /tmp/cros-keyboard-map
git clone --depth 1 --progress https://github.com/WeirdTreeThing/cros-keyboard-map.git
cd /tmp/cros-keyboard-map
./install.sh

echo "--> Installing low-spec packages (zram-tools, tlp)…"
apt-get install -y zram-tools tlp
systemctl enable tlp.service 2>/dev/null || true

echo "--> Setting vm.swappiness=20 in /etc/sysctl.conf…"
if ! grep -q '^vm.swappiness=20' /etc/sysctl.conf 2>/dev/null; then
    if grep -q '^vm.swappiness=' /etc/sysctl.conf 2>/dev/null; then
        sed -i 's/^vm.swappiness=.*/vm.swappiness=20/' /etc/sysctl.conf
    else
        echo 'vm.swappiness=20' >> /etc/sysctl.conf
    fi
    sysctl -w vm.swappiness=20
    echo "    [+] vm.swappiness=20 applied."
else
    echo "    [i] vm.swappiness=20 already configured."
fi

mark_done
echo "[${MODULE_ID}] Done."
