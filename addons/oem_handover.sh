#!/bin/bash
# Final OEM handover: disables the login manager and triggers the setup wizard.
set -euo pipefail

echo "========================================="
echo "  Prepare for OEM shipping (handover)"
echo "========================================="
echo ""
echo "This will:"
echo "  • Set the default boot target to oem-config.target"
echo "  • Stop and disable SDDM (avoids blank login screen before the wizard)"
echo "  • Run oem-config-prepare (scrub OEM logs, prepare first-boot wizard)"
echo "  • Shut down the machine immediately"
echo ""
read -r -p "Continue? [y/N]: " confirm </dev/tty || confirm="n"
case "$confirm" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
esac

if ! command -v oem-config-prepare &>/dev/null; then
    echo "Error: oem-config-prepare not found. Is the Calamares OEM package installed?" >&2
    exit 1
fi

echo "--> Preparing for OEM handover…"

echo "--> Setting default target to oem-config.target…"
systemctl set-default oem-config.target

echo "--> Stopping SDDM to prevent display manager conflicts…"
systemctl stop sddm || true
systemctl disable sddm || true

echo "--> Triggering OEM config prepare utility…"
oem-config-prepare

echo "--> Finalizing disk writes…"
sync

echo "--> Handover prepared. The system will now shut down."
shutdown -h now
