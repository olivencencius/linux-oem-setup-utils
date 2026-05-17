#!/bin/bash
# ==============================================================================
#   Module:    oem_handover.sh
#   Purpose:   Install Ubuntu OEM handover packages (oem-config, oem-config-gtk)
#              after the rest of the pipeline so a slow/heavy apt does not block
#              Plank, wallpaper, skel, touchpad, locale, or diagnostics.
#   Reads:     ensure_apt_fresh (setup.sh)
#   Writes:    apt: oem-config, oem-config-gtk
#   Step fn:   step_oem_handover
#   See:       modules/themes.sh (deploys launchers; optional apt-on-demand in
#              oem-prepare-shipping.sh — this step guarantees packages are present)
# ==============================================================================

step_oem_handover() {
    local hb_pid _ec

    oem_tty_say "--> Installing Ubuntu OEM handover packages (oem-config)…"
    oem_tty_say "    [...] Using verbose apt (-V + acquire worker debug). Large dependency set — may take many minutes."
    oem_tty_say "    [...] Heartbeat on this line every 60s while apt/dpkg is still running."

    ensure_apt_fresh

    (
        while sleep 60; do
            oem_tty_say "    [...] OEM handover apt still running ($(date -Iseconds))…"
        done
    ) &
    hb_pid=$!

    if ! oem_run_log env DEBIAN_FRONTEND=noninteractive \
        apt-get install -y -V \
        -o Debug::pkgAcquire::Worker=1 \
        oem-config oem-config-gtk
    then
        _ec=$?
        kill "$hb_pid" 2>/dev/null || true
        wait "$hb_pid" 2>/dev/null || true
        return "$_ec"
    fi

    kill "$hb_pid" 2>/dev/null || true
    wait "$hb_pid" 2>/dev/null || true

    oem_tty_say "    [+] oem-config packages installed."
}
