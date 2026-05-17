#!/bin/bash
# ==============================================================================
#   Module:    updates.sh
#   Purpose:   Bring the base system up to date and install universal
#              prerequisites (base tools, ZRAM, TLP). Exports
#              OEM_APT_FRESH=1 so later modules' ensure_apt_fresh calls no-op.
#   Reads:     (nothing — runs the real apt-get update itself)
#   Writes:    apt: git, wget, xinput, zram-tools, tlp
#              systemd: enables + starts tlp.service
#              env: exports OEM_APT_FRESH=1
#   Step fn:   step_updates
#   Docs:      docs/modules/updates.md
#   Uninstall: step_uninstall purges tlp, zram-tools, imwheel (legacy).
#                git/wget/xinput are kept. Note: GIMP is now optional
#                (step_gimp) and is managed separately.
# ==============================================================================

step_updates() {
    oem_tty_say "--> Updating package manager and running system upgrades…"
    oem_run_log apt-get update
    oem_run_log env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    export OEM_APT_FRESH=1   # other modules can skip apt-get update after this

    oem_tty_say "--> Installing base tools (git, wget, xinput)…"
    oem_run_log env DEBIAN_FRONTEND=noninteractive apt-get install -y git wget xinput

    oem_tty_say "--> Installing ZRAM (memory compression) and TLP (battery management)…"
    oem_run_log env DEBIAN_FRONTEND=noninteractive apt-get install -y zram-tools tlp
    oem_run_log systemctl enable --now tlp.service
}
