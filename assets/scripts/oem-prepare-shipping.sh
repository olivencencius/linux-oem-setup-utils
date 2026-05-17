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
#   GUI shortcut: Desktop + /usr/share/applications launcher uses pkexec on
#                 /usr/sbin/oem-config-prepare — packages must be installed
#                 (step_themes does this; this script is for terminal use or
#                 when fixing a half-installed state).
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
