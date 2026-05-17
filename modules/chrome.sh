#!/bin/bash
# ==============================================================================
#   Module:    chrome.sh
#   Purpose:   Install Google Chrome stable (amd64) from the upstream .deb.
#              Chrome's postinst registers the Google apt repository and
#              signing key so it self-updates via `apt update`.
#   Reads:     helpers: ensure_apt_fresh
#              network: dl.google.com
#              REPO_DIR/modules/chrome-exec-flags.sh (OEM_CHROME_EXEC_FLAGS)
#   Writes:    apt: google-chrome-stable
#              /tmp/google-chrome-stable_current_amd64.deb (transient)
#              /etc/apt/sources.list.d/google-chrome.list  (via postinst)
#              /usr/share/keyrings/google-chrome.gpg       (via postinst)
#              /usr/share/applications/google-chrome.desktop — vendor file
#                patched in-place with OEM_CHROME_EXEC_FLAGS (same as web apps;
#                see modules/chrome-exec-flags.sh). Consumed by Plank.
#   Step fn:   step_chrome
#   Docs:      docs/modules/chrome.md
#   Uninstall: step_uninstall purges google-chrome-stable AND removes the
#              Google apt repo file and signing key (sub-steps 2, 2b).
#
#   NOTE: Chrome is NOT optional — an empty download returns non-zero and
#   aborts the pipeline. Web-app shortcuts and several dockitems depend on
#   /usr/share/applications/google-chrome.desktop existing.
# ==============================================================================

# shellcheck source=chrome-exec-flags.sh
source "$REPO_DIR/modules/chrome-exec-flags.sh"

# Patch vendor google-chrome.desktop so main Chrome matches web-app launchers
# (no gnome-keyring prompt). Idempotent; safe to re-run after apt upgrades
# replace the file. See docs/modules/chrome.md.
patch_google_chrome_desktop() {
    local desktop_file="/usr/share/applications/google-chrome.desktop"
    [ -f "$desktop_file" ] || return 0

    local tmp
    tmp=$(mktemp)
    local changed=0
    local line

    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^Exec= ]] && [[ "$line" == *google-chrome* ]] \
            && [[ "$line" != *--password-store=basic* ]]; then
            if [[ "$line" =~ ^Exec=(.*google-chrome[^%]*)([[:space:]]+%.*)$ ]]; then
                line="Exec=${BASH_REMATCH[1]} ${OEM_CHROME_EXEC_FLAGS}${BASH_REMATCH[2]}"
            else
                line="${line} ${OEM_CHROME_EXEC_FLAGS}"
            fi
            changed=1
        fi
        printf '%s\n' "$line"
    done < "$desktop_file" > "$tmp"

    if [ "$changed" -eq 1 ]; then
        cat "$tmp" > "$desktop_file"
        oem_tty_say "    [+] Patched google-chrome.desktop (keyring + overlay scrollbar flags)."
    fi
    rm -f "$tmp"
}

step_chrome() {
    oem_tty_say "--> Downloading Google Chrome .deb (network)…"
    local deb=/tmp/google-chrome-stable_current_amd64.deb

    rm -f "$deb"
    oem_run_log wget -q --show-progress -O "$deb" \
        https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

    if [ ! -s "$deb" ]; then
        oem_tty_say "    [!] Chrome .deb download failed or empty — aborting step."
        rm -f "$deb"
        return 1
    fi

    ensure_apt_fresh
    oem_tty_say "--> Installing Google Chrome package…"
    oem_run_log env DEBIAN_FRONTEND=noninteractive apt-get install -y "$deb"
    rm -f "$deb"

    patch_google_chrome_desktop
}
