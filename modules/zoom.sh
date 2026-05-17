#!/bin/bash
# ==============================================================================
#   Module:    zoom.sh
#   Purpose:   Install the official Zoom desktop client from the upstream
#              amd64 .deb. The .deb ships its own
#              /usr/share/applications/Zoom.desktop (capital Z), which the
#              Plank zoom.dockitem references.
#   Reads:     helpers: ensure_apt_fresh
#              network: zoom.us
#   Writes:    apt: zoom
#              /tmp/zoom_amd64.deb (transient)
#   Step fn:   step_zoom
#   Docs:      docs/modules/zoom.md
#   Uninstall: step_uninstall purges 'zoom' (sub-step 2). Zoom registers no
#              apt repo or signing key — nothing else to clean up.
#
#   NOTE: Zoom is "nice to have". A download failure is non-fatal: the module
#   prints a warning and returns 0; the rest of the pipeline continues; the
#   Plank dock will be short by one icon (zoom.dockitem references a missing
#   .desktop and Plank silently skips it).
# ==============================================================================

step_zoom() {
    oem_tty_say "--> Downloading Zoom .deb (network; optional step)…"
    local deb=/tmp/zoom_amd64.deb

    rm -f "$deb"
    # Zoom is "nice to have" — we explicitly tolerate a download failure
    # (e.g. flaky CDN) and just skip the install, instead of aborting the
    # whole pipeline. `|| true` keeps `set -e` from biting us.
    oem_run_log wget -q --show-progress -O "$deb" https://zoom.us/client/latest/zoom_amd64.deb || true

    if [ ! -s "$deb" ]; then
        oem_tty_say "    [!] Zoom .deb download failed — skipping."
        rm -f "$deb"
        return 0
    fi

    ensure_apt_fresh
    oem_tty_say "--> Installing Zoom package…"
    oem_run_log env DEBIAN_FRONTEND=noninteractive apt-get install -y "$deb"
    rm -f "$deb"
    oem_tty_say "    [+] Zoom installed."
}
