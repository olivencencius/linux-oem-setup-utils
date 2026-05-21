#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/var/lib/lubuntu-oem-setup}"
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

echo "--> Installing low-spec packages (tlp, systemd-zram-generator)…"
# Purge zram-tools to prevent conflicts with the native systemd-zram-generator
apt-get purge -y zram-tools || true
apt-get install -y tlp systemd-zram-generator
systemctl enable tlp.service 2>/dev/null || true

echo "--> Configuring ZRAM via systemd-zram-generator (50% of RAM, LZ4 compression)..."
mkdir -p /etc/systemd/zram-generator.conf.d
cat > /etc/systemd/zram-generator.conf.d/zram.conf <<EOF
[zram0]
zram-size = ram / 2
compression-algorithm = lz4
EOF

systemctl daemon-reload

# Attempt to initialize ZRAM now. 
# We remove '|| true' so you get an error if this fails, 
# ensuring you don't ship a unit with broken memory management.
if ! systemctl start systemd-zram-setup@zram0.service; then
    echo "    [!] Warning: Could not hot-start ZRAM. It will initialize cleanly on the next reboot."
else
    echo "    [+] ZRAM initialized and active."
fi

echo "--> Setting vm.swappiness=10 to protect eMMC wear-and-tear…"
echo "vm.swappiness=10" > /etc/sysctl.d/99-custom-swappiness.conf
sysctl -p /etc/sysctl.d/99-custom-swappiness.conf
echo "    [+] vm.swappiness=10 applied."

mark_done
echo "[${MODULE_ID}] Done."