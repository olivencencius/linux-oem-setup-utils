#!/bin/bash
# ==============================================================================
#   Module:    cleanup.sh
#   Purpose:   Remove leftover /tmp artefacts from previous partial runs so
#              install steps always start from a clean slate.
#   Reads:     (nothing)
#   Writes:    /tmp/{chromebook-linux-audio,cros-keyboard-map,
#                    ChromeOS-theme,Tela-icon-theme}                (rm -rf)
#              /tmp/{google-chrome-stable_current_amd64.deb,
#                    zoom_amd64.deb,touchegg.deb}                   (rm -f)
#   Step fn:   step_cleanup
#   Docs:      docs/modules/cleanup.md
#   Uninstall: step_uninstall calls step_cleanup itself near the end (no undo
#              needed — every removed path is a re-fetchable download/clone).
# ==============================================================================

step_cleanup() {
    oem_tty_say "--> Cleaning up temporary files from any previous partial runs..."
    rm -rf /tmp/chromebook-linux-audio \
           /tmp/cros-keyboard-map \
           /tmp/ChromeOS-theme \
           /tmp/Tela-icon-theme
    rm -f  /tmp/google-chrome-stable_current_amd64.deb \
           /tmp/zoom_amd64.deb \
           /tmp/touchegg.deb
}
