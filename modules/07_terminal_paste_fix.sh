#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/var/lib/xubuntu-oem-setup}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/.state}"
MODULE_ID="07_terminal_paste_fix"

is_done() { [ -f "$STATE_FILE" ] && grep -qxF "$MODULE_ID" "$STATE_FILE"; }
mark_done() { mkdir -p "$STATE_DIR"; grep -qxF "$MODULE_ID" "$STATE_FILE" || echo "$MODULE_ID" >> "$STATE_FILE"; }

if is_done; then
    echo "[${MODULE_ID}] Already completed — skipping."
    exit 0
fi

echo "--> Disabling bracketed paste globally (/etc/inputrc)…"
touch /etc/inputrc
if ! grep -q 'set enable-bracketed-paste off' /etc/inputrc; then
    echo 'set enable-bracketed-paste off' >> /etc/inputrc
    echo "    [+] Appended to /etc/inputrc"
else
    echo "    [i] Already set in /etc/inputrc"
fi

mark_done
echo "[${MODULE_ID}] Done."
