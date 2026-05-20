#!/bin/bash
# Prepare the machine for the end customer (Ubuntu/Xubuntu OEM flow).
set -euo pipefail

if [ "${EUID:-}" -ne 0 ]; then
    echo "Error: run as root (e.g. sudo bash prepare_for_shipping.sh)" >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

if ! command -v oem-config-prepare &>/dev/null; then
    echo "--> Installing oem-config packages…"
    apt-get update
    apt-get install -y oem-config oem-config-gtk
fi

echo "--> Running oem-config-prepare (removes OEM user; first-boot setup wizard for buyer)…"
exec /usr/sbin/oem-config-prepare "$@"
