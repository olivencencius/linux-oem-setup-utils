#!/bin/bash
# ==============================================================================
#   Script:       oem-prepare-shipping.sh
#   Purpose:      Prepare an Xubuntu LTS image for the end user (Ubuntu OEM /
#                 ubiquity oem-config flow). Installs oem-config packages if
#                 needed, then runs oem-config-prepare.
#
#   Installed to: /usr/local/bin/oem-prepare-shipping (mode 755)
#   Installed by: modules/themes.sh
#   Runs as:      root (re-exec: sudo oem-prepare-shipping)
#
#   GUI shortcut: Desktop + menu launchers use pkexec on this script (same as
#                 sudo oem-prepare-shipping) so oem-config can be installed on
#                 demand and behaviour matches the terminal path.
#
#   Remote run (handover only — not bootstrap.sh):
#     wget -qO- https://raw.githubusercontent.com/olivencencius/linux-oem-setup-utils/main/assets/scripts/oem-prepare-shipping.sh | sudo bash
# ==============================================================================

set -Eeuo pipefail

if [ "${EUID:-}" -ne 0 ]; then
    echo "oem-prepare-shipping: run as root (sudo oem-prepare-shipping)" >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

if ! command -v oem-config-prepare &>/dev/null; then
    echo "--> Installing oem-config packages…"
    apt-get update -qq
    apt-get install -y oem-config oem-config-gtk
fi

exec /usr/sbin/oem-config-prepare "$@"
