#!/bin/bash
# ==============================================================================
#   Module:    updates.sh
#   Purpose:   Bring the base system up to date and install universal
#              prerequisites (codecs, base tools, ZRAM, TLP). Exports
#              OEM_APT_FRESH=1 so later modules' ensure_apt_fresh calls no-op.
#   Reads:     (nothing — runs the real apt-get update itself)
#   Writes:    apt: mint-meta-codecs, git, wget, curl, xinput, gimp,
#                   gtk2-engines-murrine, zram-tools, tlp
#              systemd: enables + starts tlp.service
#              env: exports OEM_APT_FRESH=1
#   Step fn:   step_updates
#   Docs:      docs/modules/updates.md
#   Uninstall: step_uninstall purges tlp, zram-tools, mint-meta-codecs,
#                imwheel (legacy), gimp (sub-step 2). gtk2-engines-murrine
#                is intentionally kept — it's a tiny shared GTK2 dependency
#                used by many other themes too. git/wget/curl/xinput also kept.
# ==============================================================================

step_updates() {
    echo "--> Updating package manager and running system updates..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    export OEM_APT_FRESH=1   # other modules can skip apt-get update after this

    # gtk2-engines-murrine is required by Mint-Y-Aqua (and most other GTK
    # themes) to render GTK2 widgets correctly (XFCE panel plugins, older
    # apps). Without it the theme is selected but visually inert on GTK2
    # widgets. Installed here (not in themes.sh) because it is a universal
    # base dependency independent of which visual theme is chosen.
    # NOTE: papirus-icon-theme is installed by step_themes, not here — it
    # is only needed when the theme step runs.
    echo "--> Installing codecs and base tools..."
    apt-get install -y mint-meta-codecs git wget curl xinput gimp \
                       gtk2-engines-murrine

    echo "--> Installing ZRAM (memory compression) and TLP (battery management)..."
    apt-get install -y zram-tools tlp
    systemctl enable --now tlp.service
}
