#!/bin/bash
# ==============================================================================
#   Module:    chrome.sh
#   Purpose:   Install Google Chrome stable (amd64) from the upstream .deb.
#              Chrome's postinst registers the Google apt repository and
#              signing key so it self-updates via `apt update`.
#   Reads:     helpers: ensure_apt_fresh
#              network: dl.google.com
#   Writes:    apt: google-chrome-stable
#              /tmp/google-chrome-stable_current_amd64.deb (transient)
#              /etc/apt/sources.list.d/google-chrome.list  (via postinst)
#              /usr/share/keyrings/google-chrome.gpg       (via postinst)
#              /usr/share/applications/google-chrome.desktop (consumed by
#                the Plank google-chrome.dockitem)
#   Step fn:   step_chrome
#   Docs:      docs/modules/chrome.md
#   Uninstall: step_uninstall purges google-chrome-stable AND removes the
#              Google apt repo file and signing key (sub-steps 2, 2b).
#
#   NOTE: Chrome is NOT optional — an empty download returns non-zero and
#   aborts the pipeline. Web-app shortcuts and several dockitems depend on
#   /usr/share/applications/google-chrome.desktop existing.
# ==============================================================================

step_chrome() {
    echo "--> Downloading and installing Google Chrome..."
    local deb=/tmp/google-chrome-stable_current_amd64.deb

    rm -f "$deb"
    wget -q --show-progress -O "$deb" \
        https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

    if [ ! -s "$deb" ]; then
        echo "    [!] Chrome .deb download failed or empty — aborting step."
        rm -f "$deb"
        return 1
    fi

    ensure_apt_fresh
    apt-get install -y "$deb"
    rm -f "$deb"
}
