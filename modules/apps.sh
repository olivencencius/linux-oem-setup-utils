#!/bin/bash
# ==============================================================================
#   Module:    apps.sh
#   Purpose:   Install default user-facing apt apps: VLC + three games
#              (supertuxkart, aisleriot, quadrapassel). Native apt keeps disk
#              use low on 4 GB eMMC.
#   Reads:     helpers: ensure_apt_fresh
#   Writes:    apt: vlc, supertuxkart, aisleriot, quadrapassel
#              /usr/share/applications/vlc.desktop (consumed by Plank
#                vlc.dockitem)
#   Step fn:   step_apps
#   Docs:      docs/modules/apps.md
#   Uninstall: step_uninstall purges vlc, supertuxkart, aisleriot,
#              quadrapassel (sub-step 2). GIMP lives in step_updates, not
#              here. Spotify is a web app via step_web_apps.
# ==============================================================================

step_apps() {
    echo "--> Installing default applications..."
    ensure_apt_fresh
    apt-get install -y vlc supertuxkart aisleriot quadrapassel
}
