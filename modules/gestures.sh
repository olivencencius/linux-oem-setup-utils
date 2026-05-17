#!/bin/bash
# ==============================================================================
#   Module:    gestures.sh
#   Purpose:   ChromeOS-like multi-finger touchpad gestures via touchegg
#              (pinch zoom, 3/4-finger swipes for back/forward, overview,
#              show-desktop, workspaces, whisker menu), plus xfdashboard
#              workspace/window overview and a system launcher for Plank.
#   Reads:     REPO_DIR/assets/configs/touchegg.conf
#              REPO_DIR/assets/configs/oem-workspace-overview.desktop
#              SUDO_USER (optional, for live-session client)
#              helpers: ensure_apt_fresh
#   Writes:    apt: wmctrl, xdotool, touchegg (repo, PPA, or GitHub .deb), xfdashboard
#              /usr/share/applications/oem-workspace-overview.desktop
#              /etc/touchegg/touchegg.conf
#              systemd: enables + starts touchegg.service
#              runs: touchegg --client for SUDO_USER (background)
#   Step fn:   step_gestures_and_workspaces
#   Docs:      docs/modules/gestures.md
#   Uninstall: step_uninstall stops touchegg + kills clients (sub-step 1),
#              purges touchegg/xfdashboard/wmctrl/xdotool (sub-step 2),
#              removes /etc/touchegg/touchegg.conf, oem-workspace-overview.desktop,
#              and the touchegg client autostart entry in skel and per-user
#              (sub-steps 7, 8, 12, 13).
#
#   NOTE: WHY TOUCHEGG, NOT libinput-gestures? touchegg runs the libinput
#   reader as a SYSTEM service and dispatches to per-user clients over
#   D-Bus, so no buyer needs to be added to the `input` group after
#   handover. xfdashboard is the Xfce window/workspace overview for the
#   3-finger swipe-up gesture and the Plank “overview” pin; it must be
#   installed before step_themes runs oem-first-run.sh so the dockitem exists.
# ==============================================================================

# Touchegg lives in Ubuntu “universe”; minimal / OEM images sometimes ship with
# only main, which yields: “package touchegg is not available but is referred
# to by another package”. Fall back to ppa:touchegg/stable, then to the official
# GitHub .deb (same bits upstream publishes)—works when mirrors/Launchpad are broken.
_gestures_touchegg_candidate() {
    apt-cache policy touchegg 2>/dev/null | sed -n 's/^[[:space:]]*Candidate:[[:space:]]*//p' | head -n1
}

# Pin occasionally for reproducible OEM runs. Override full URL with TOUCHEGG_DEB_URL.
_gestures_install_touchegg_from_github_deb() {
    local ver td url deb arch
    ver="${TOUCHEGG_DEB_VERSION:-2.0.18}"
    arch="$(uname -m)"
    case "$arch" in
        x86_64) deb="touchegg_${ver}_amd64.deb" ;;
        *)
            oem_tty_say \
                "    [!] GitHub .deb fallback is only published for x86_64 (this system is ${arch})."
            return 1
            ;;
    esac

    if [ -n "${TOUCHEGG_DEB_URL:-}" ]; then
        url="$TOUCHEGG_DEB_URL"
    else
        url="https://github.com/JoseExposito/touchegg/releases/download/${ver}/${deb}"
    fi

    td=$(mktemp -d "${TMPDIR:-/tmp}/oem-touchegg.XXXXXX") || return 1

    # GNU wget: --show-progress needs stderr on a real TTY (see modules/chrome.sh).
    oem_tty_say "--> Downloading touchegg .deb…" "    [.] ${url}"
    oem_tty_say "    [.] Starting wget…"
    if ! wget \
        --continue \
        --show-progress \
        --timeout=30 \
        --tries=3 \
        -O "$td/$deb" \
        "$url" \
        2>&3
    then
        oem_tty_say \
            "    [!] wget failed — check network or set TOUCHEGG_DEB_URL to a local copy (supports file:///…)."
        rm -rf "$td"
        return 1
    fi

    if [ ! -s "$td/$deb" ]; then
        oem_tty_say "    [!] Downloaded .deb is missing or empty."
        rm -rf "$td"
        return 1
    fi

    oem_tty_say "--> Installing touchegg from downloaded .deb (apt resolves dependencies)…"
    env DEBIAN_FRONTEND=noninteractive apt-get install -y "$td/$deb" </dev/null >&3 2>&3
    local ec=$?
    rm -rf "$td"
    return "$ec"
}

_gestures_touchegg_pkg_installed() {
    dpkg-query -W -f='${Status}' touchegg 2>/dev/null | grep -q 'install ok installed'
}

_gestures_ensure_touchegg_apt_source() {
    local cand
    cand="$(_gestures_touchegg_candidate)"
    if [[ -n "$cand" && "$cand" != "(none)" ]]; then
        return 0
    fi

    if ! command -v add-apt-repository >/dev/null 2>&1; then
        oem_tty_say "--> Installing software-properties-common (for apt repositories)…"
        env DEBIAN_FRONTEND=noninteractive apt-get install -y \
            software-properties-common </dev/null >&3 2>&3
    fi

    oem_tty_say "--> touchegg not in apt (Candidate empty); enabling \"universe\"…"
    env DEBIAN_FRONTEND=noninteractive add-apt-repository -y universe \
        </dev/null >&3 2>&3 || true
    unset OEM_APT_FRESH 2>/dev/null || true
    ensure_apt_fresh

    cand="$(_gestures_touchegg_candidate)"
    if [[ -n "$cand" && "$cand" != "(none)" ]]; then
        return 0
    fi

    oem_tty_say "--> touchegg still unavailable; adding ppa:touchegg/stable…"
    env DEBIAN_FRONTEND=noninteractive add-apt-repository -y ppa:touchegg/stable \
        </dev/null >&3 2>&3 || true
    unset OEM_APT_FRESH 2>/dev/null || true
    ensure_apt_fresh

    cand="$(_gestures_touchegg_candidate)"
    if [[ -n "$cand" && "$cand" != "(none)" ]]; then
        return 0
    fi

    oem_tty_say "--> touchegg still not in apt; installing official .deb from GitHub…"
    if _gestures_install_touchegg_from_github_deb && _gestures_touchegg_pkg_installed; then
        unset OEM_APT_FRESH 2>/dev/null || true
        ensure_apt_fresh
        return 0
    fi

    oem_tty_say \
        "    [!] touchegg could not be installed. Fix apt/network or pre-stage a .deb and set TOUCHEGG_DEB_URL."
    return 1
}

step_gestures_and_workspaces() {
    oem_tty_say "--> Installing touchpad gestures (touchegg) and workspace overview (xfdashboard)…"

    ensure_apt_fresh
    _gestures_ensure_touchegg_apt_source

    # apt exit 100 = install failure; errors must be visible (same TTY issue as Chrome wget).
    oem_tty_say \
        "--> apt: installing wmctrl, xdotool, touchegg, xfdashboard…" \
        "    [.] If this fails with exit 100, read the apt message below — broken dpkg (sudo dpkg --configure -a), conflicts, or network."
    env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        wmctrl xdotool touchegg xfdashboard \
        </dev/null >&3 2>&3

    install -m 644 "$REPO_DIR/assets/configs/oem-workspace-overview.desktop" \
        /usr/share/applications/oem-workspace-overview.desktop
    oem_tty_say "    [+] /usr/share/applications/oem-workspace-overview.desktop"

    if command -v update-desktop-database &>/dev/null; then
        oem_run_log update-desktop-database /usr/share/applications 2>/dev/null || true
    fi

    # -------------------------------------------------------------------------
    # Deploy ChromeOS-like binding profile (system-wide)
    # -------------------------------------------------------------------------
    mkdir -p /etc/touchegg
    install -m 644 "$REPO_DIR/assets/configs/touchegg.conf" \
                   /etc/touchegg/touchegg.conf
    oem_tty_say "    [+] /etc/touchegg/touchegg.conf written."

    # -------------------------------------------------------------------------
    # Enable the system daemon (per-user clients connect to it over D-Bus)
    # -------------------------------------------------------------------------
    systemctl enable --now touchegg.service 2>/dev/null || true
    if systemctl is-active --quiet touchegg.service; then
        oem_tty_say "    [+] touchegg.service is active."
    else
        oem_tty_say "    [!] touchegg.service is NOT active — gestures will not work until it starts."
    fi

    # -------------------------------------------------------------------------
    # Live oem session — start the client so the technician can verify
    # gestures during QA before handover. New users get the client via the
    # skel autostart (.config/autostart/touchegg-client.desktop).
    # -------------------------------------------------------------------------
    if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null; then
        local USER_HOME
        USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

        sudo -u "$SUDO_USER" pkill -f 'touchegg --client' 2>/dev/null || true
        sudo -u "$SUDO_USER" \
            DISPLAY="${DISPLAY:-:0}" \
            XAUTHORITY="$USER_HOME/.Xauthority" \
            touchegg --client 2>/dev/null &

        oem_tty_say "    [+] touchegg client started for $SUDO_USER."
    else
        oem_tty_say "    [i] \$SUDO_USER not set — client autostart on next login only."
    fi

    # Legacy step id was `gestures`; drop its marker so resume matches setup.sh.
    rm -f "${STATE_DIR:-/var/lib/oem-setup/state}/gestures.done" 2>/dev/null || true
}
