#!/bin/bash
# ==============================================================================
#   Module:    updates.sh
#   Purpose:   Bring the base system up to date and install universal
#              prerequisites (codecs, base tools, ZRAM, TLP). Exports
#              OEM_APT_FRESH=1 so later modules' ensure_apt_fresh calls no-op.
#   Reads:     (nothing — runs the real apt-get update itself)
#   Writes:    apt: git, wget, curl, xinput, gimp, zram-tools, tlp
#              systemd: enables + starts tlp.service
#              env: exports OEM_APT_FRESH=1
#   Step fn:   step_updates
#   Docs:      docs/modules/updates.md
#   Uninstall: step_uninstall purges tlp, zram-tools, imwheel (legacy),
#                gimp (sub-step 2). git/wget/curl/xinput are kept.
# ==============================================================================

step_updates() {
    echo "--> Updating package manager and running system updates..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    export OEM_APT_FRESH=1   # other modules can skip apt-get update after this

    echo "--> Installing base tools..."
    apt-get install -y git wget curl xinput gimp

    echo "--> Installing ZRAM (memory compression) and TLP (battery management)..."
    apt-get install -y zram-tools tlp
    systemctl enable --now tlp.service
}
