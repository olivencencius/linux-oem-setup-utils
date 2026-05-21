#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/var/lib/lubuntu-oem-setup}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/.state}"
MODULE_ID="03_boot_optimization"

is_done() { [ -f "$STATE_FILE" ] && grep -qxF "$MODULE_ID" "$STATE_FILE"; }
mark_done() { mkdir -p "$STATE_DIR"; grep -qxF "$MODULE_ID" "$STATE_FILE" || echo "$MODULE_ID" >> "$STATE_FILE"; }

if is_done; then
    echo "[${MODULE_ID}] Already completed — skipping."
    exit 0
fi

echo "--> Masking network wait-online services (prevents offline boot hangs)…"
for svc in systemd-networkd-wait-online.service NetworkManager-wait-online.service; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}"; then
        systemctl mask --now "$svc" 2>/dev/null || true
        echo "    [+] Masked $svc"
    fi
done

echo "--> No graphics or hardware boot optimizations to perform."
echo "    (AMD hardware delays are firmware-locked; Intel boots optimally by default)."

mark_done
echo "[${MODULE_ID}] Done."