#!/bin/bash
# ==============================================================================
#   Module:    flathub.sh
#   Purpose:   Add the Flathub remote so the buyer can install flatpak apps
#              later. This toolkit installs NO flatpaks itself — apt is
#              preferred to save the ~1.5 GB GNOME/freedesktop runtime on a
#              4 GB eMMC.
#   Reads:     (nothing)
#   Writes:    flatpak system config: 'flathub' remote pointing at
#              https://flathub.org/repo/flathub.flatpakrepo
#   Step fn:   step_flathub
#   Docs:      docs/modules/flathub.md
#   Uninstall: step_uninstall runs `flatpak remote-delete --force flathub`
#              (sub-step 3).
# ==============================================================================

step_flathub() {
    echo "--> Setting up Flathub repository for future buyer installs..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak update -y || true
}
