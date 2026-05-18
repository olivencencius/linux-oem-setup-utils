#!/bin/bash
# ==============================================================================
#   Script:       oem-prepare-shipping.sh
#   Purpose:      Prepare an Xubuntu LTS image for the end user (Ubuntu OEM /
#                 ubiquity oem-config flow). Installs oem-config packages if
#                 needed, then runs oem-config-prepare.
#
#   Distribution: Not installed by the toolkit pipeline. Run this file directly
#                 (or wget/curl the raw script from GitHub) when you hand over.
#                 Optional: copy to /usr/local/bin/oem-prepare-shipping (755) if
#                 you want a stable path or a custom .desktop with pkexec.
#   Runs as:      root
#
#   Remote run (handover only — not bootstrap.sh):
#     wget -qO- https://raw.githubusercontent.com/olivencencius/linux-oem-setup-utils/main/assets/scripts/oem-prepare-shipping.sh | sudo bash
# ==============================================================================

set -Eeuo pipefail

if [ "${EUID:-}" -ne 0 ]; then
    echo "oem-prepare-shipping: run as root (e.g. sudo bash oem-prepare-shipping.sh, or wget … | sudo bash)" >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

if ! command -v oem-config-prepare &>/dev/null; then
    echo "--> Installing oem-config packages…"
    apt-get update -qq
    apt-get install -y oem-config oem-config-gtk
fi

exec /usr/sbin/oem-config-prepare "$@"
