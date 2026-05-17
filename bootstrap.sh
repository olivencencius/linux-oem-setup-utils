#!/bin/bash
# ==============================================================================
#   Chromebook OEM Bootstrap
#   Downloads the full deployment toolkit and launches the setup menu.
#
#   Run this single command from the oem terminal:
#     wget -qO- https://raw.githubusercontent.com/olivencencius/linux-oem-setup-utils/main/bootstrap.sh | sudo bash
# ==============================================================================

set -Eeuo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run this script with sudo."
    exit 1
fi

REPO_URL="https://github.com/olivencencius/linux-oem-setup-utils.git"
REPO_DIR="/var/cache/oem-setup-repo"

echo "========================================="
echo "      CHROMEBOOK DEPLOYMENT BOOTSTRAP    "
echo "========================================="

# Ensure git is available — minimal Xubuntu images may omit it
if ! command -v git &>/dev/null; then
    echo "--> git not found — installing..."
    apt-get update -qq
    apt-get install -y git
fi

# Clone or refresh the repo. If a fast-forward pull fails (local edits, diverged
# branch, dirty tree), wipe and re-clone so a stale checkout never bites us.
if [ -d "$REPO_DIR/.git" ]; then
    echo "--> Updating existing local copy of deployment toolkit..."
    if ! git -C "$REPO_DIR" pull --ff-only; then
        echo "    [!] Fast-forward pull failed — re-cloning a clean copy."
        rm -rf "$REPO_DIR"
        git clone "$REPO_URL" "$REPO_DIR"
    fi
else
    echo "--> Cloning deployment toolkit..."
    rm -rf "$REPO_DIR"
    git clone "$REPO_URL" "$REPO_DIR"
fi

echo "--> Launching setup..."
echo ""

exec bash "$REPO_DIR/setup.sh"
