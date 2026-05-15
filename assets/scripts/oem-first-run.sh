#!/bin/bash
# ==============================================================================
#   Script:       oem-first-run.sh
#   Purpose:      Per-user one-shot. On first XFCE login:
#                   1. Applies the Malta wallpaper to every detected monitor.
#                   2. Sets Mint-Y-Aqua GTK theme + Papirus icons via xsettings
#                      and xfwm4 (window decorations).
#                   3. Creates a bottom panel-2 as a ChromeOS-style dock with
#                      11 pinned launchers centered at 48 px height.
#                 Then self-deletes its autostart entry so the user keeps full
#                 freedom over theme/wallpaper/dock afterwards.
#   Installed to: /usr/local/bin/oem-first-run.sh   (mode 755)
#   Installed by: modules/themes.sh
#   Runs as:      the buyer (per user, on first login)
#   Also called:  inline by step_themes for the live oem session (with correct
#                 HOME / DBUS_SESSION_BUS_ADDRESS set by oem_user_xrun)
#   Triggered by: skel/.config/autostart/oem-first-run.desktop
#                 (staged into /etc/skel by step_themes)
#   Marker:       ~/.config/.oem-first-run-done  (created at end, checked at start)
#   Reads:        /usr/share/backgrounds/oem-setup/malta.jpg
#                 xfconf-query (xfce4-desktop channel) for monitor list
#                 xfconf-query (xfce4-panel channel) to check/create panel-2
#                 /usr/share/applications/*.desktop for each pinned launcher
#   Writes:       xfconf-query: xfce4-desktop  ./<monitor>/last-image,
#                                               ./<monitor>/image-style=5
#                 xfconf-query: xsettings       /Net/ThemeName=Mint-Y-Aqua
#                                               /Net/IconThemeName=Papirus
#                 xfconf-query: xfwm4           /general/theme=Mint-Y-Aqua
#                 xfconf-query: xfce4-panel     /panels (add panel 2),
#                                               /panels/panel-2/*,
#                                               /plugins/plugin-<N> per launcher
#                 ~/.config/xfce4/panel/launcher-<N>/ per launcher
#                 ~/.config/.oem-first-run-done
#                 rm ~/.config/autostart/oem-first-run.desktop
#   Uninstall:    step_uninstall removes the marker, the autostart entry, the
#                 panel-2 launcher dirs, and this script (sub-steps 8, 13).
#
#   NOTE: monitor discovery enumerates every `last-image` property xfconf
#   already knows about, falling back to /backdrop/screen0/monitor0/
#   workspace0/last-image when xfdesktop has not yet registered any monitor.
#   This avoids hardcoding monitor names (eDP-1, monitorVirtual1, …) which
#   vary across Chromebook hardware.
#
#   NOTE — panel-2 dock: we append a second panel rather than modifying
#   panel-1, so Mint's default top panel is left completely untouched.
#   The dock uses XFCE's built-in launcher plugin — no additional packages.
#   Plugin IDs are allocated from 100+ to avoid colliding with panel-1's
#   plugins. The idempotency check (grep -qx 2 on /panels) means re-running
#   this script is safe.
# ==============================================================================

MARKER="$HOME/.config/.oem-first-run-done"
[ -f "$MARKER" ] && exit 0

WALLPAPER="/usr/share/backgrounds/oem-setup/malta.jpg"

# Ordered list of pinned dock apps.
# Each entry is the .desktop basename WITHOUT the .desktop extension.
# The exact capitalisation must match /usr/share/applications/<name>.desktop.
DOCK_LAUNCHERS=(
    google-chrome
    xfce4-settings-manager
    thunar
    vlc
    Zoom
    Gmail
    GoogleDocs
    GoogleDrive
    Gemini
    YouTube
    Spotify
)

# ------------------------------------------------------------------------------
# 1. Wallpaper
# Detect every monitor xfdesktop already knows about and overwrite its
# wallpaper. Falls back to a known-good default path when xfdesktop has not
# yet registered any monitor (brand-new session).
# ------------------------------------------------------------------------------
if [ -f "$WALLPAPER" ] && command -v xfconf-query >/dev/null; then
    props=$(xfconf-query -c xfce4-desktop -lv 2>/dev/null \
            | awk '/last-image/ {print $1}')

    if [ -z "$props" ]; then
        props="/backdrop/screen0/monitor0/workspace0/last-image"
    fi

    while read -r prop; do
        [ -z "$prop" ] && continue
        xfconf-query -c xfce4-desktop -p "$prop" \
                     -n -t string -s "$WALLPAPER" 2>/dev/null || \
        xfconf-query -c xfce4-desktop -p "$prop" -s "$WALLPAPER" 2>/dev/null
        style_prop="${prop%/last-image}/image-style"
        xfconf-query -c xfce4-desktop -p "$style_prop" \
                     -n -t int -s 5 2>/dev/null || \
        xfconf-query -c xfce4-desktop -p "$style_prop" -s 5 2>/dev/null
    done <<< "$props"
fi

# ------------------------------------------------------------------------------
# 2. Theme + icons
# Set GTK theme, icon theme, and window-decoration theme.
# ------------------------------------------------------------------------------
if command -v xfconf-query >/dev/null; then
    xfconf-query -c xsettings -p /Net/ThemeName     -s "Mint-Y-Aqua" 2>/dev/null || true
    xfconf-query -c xsettings -p /Net/IconThemeName -s "Papirus"     2>/dev/null || true
    xfconf-query -c xfwm4     -p /general/theme     -s "Mint-Y-Aqua" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 3. Bottom panel-2 dock
# Creates an XFCE panel at the bottom of the screen with the 11 pinned
# launchers centered. Skips silently if panel-2 already exists.
# ------------------------------------------------------------------------------
setup_dock_panel() {
    command -v xfconf-query >/dev/null || return 0

    # Idempotency: bail out if panel 2 is already listed.
    if xfconf-query -c xfce4-panel -p /panels 2>/dev/null | grep -qx 2; then
        return 0
    fi

    # Build the full -t int -s N -t int -s M ... argument list for /panels,
    # preserving whatever panels already exist plus our new panel 2.
    local panel_args=()
    while IFS= read -r existing_id; do
        [ -n "$existing_id" ] && panel_args+=( -t int -s "$existing_id" )
    done < <(xfconf-query -c xfce4-panel -p /panels 2>/dev/null || true)
    panel_args+=( -t int -s 2 )

    # Register panel 2 in the /panels array.
    xfconf-query -c xfce4-panel -p /panels \
        --create -a "${panel_args[@]}" 2>/dev/null || true

    # Panel geometry and appearance.
    # position p=8 = bottom-centre (XFCE GravityType: 8 = NETHER_CENTER).
    # length=1 with length-adjust=true means "shrink to fit contents" (dock style).
    # background-style=1 (solid colour) + semi-transparent black RGBA.
    xfconf-query -c xfce4-panel -p /panels/panel-2/position \
        --create -t string -s "p=8;x=0;y=0" 2>/dev/null || true
    xfconf-query -c xfce4-panel -p /panels/panel-2/position-locked \
        --create -t bool -s true 2>/dev/null || true
    xfconf-query -c xfce4-panel -p /panels/panel-2/length \
        --create -t uint -s 1 2>/dev/null || true
    xfconf-query -c xfce4-panel -p /panels/panel-2/length-adjust \
        --create -t bool -s true 2>/dev/null || true
    xfconf-query -c xfce4-panel -p /panels/panel-2/size \
        --create -t uint -s 48 2>/dev/null || true
    xfconf-query -c xfce4-panel -p /panels/panel-2/autohide-behavior \
        --create -t uint -s 0 2>/dev/null || true
    xfconf-query -c xfce4-panel -p /panels/panel-2/background-style \
        --create -t uint -s 1 2>/dev/null || true
    xfconf-query -c xfce4-panel -p /panels/panel-2/background-rgba \
        --create -a -t double -s 0.0 -t double -s 0.0 \
                    -t double -s 0.0 -t double -s 0.5 2>/dev/null || true

    # Allocate plugin IDs starting at 100 to avoid colliding with panel-1 plugins.
    local next_pid
    next_pid=$(xfconf-query -c xfce4-panel -l 2>/dev/null \
               | sed -n 's|^/plugins/plugin-\([0-9]*\)$|\1|p' \
               | sort -n | tail -1)
    # If no plugins exist at all, start at 99 so the first ++ gives 100.
    next_pid=$(( ${next_pid:-99} + 1 ))
    [ "$next_pid" -lt 100 ] && next_pid=100

    # Create one launcher plugin per pinned app.
    local pid pids=()
    for app in "${DOCK_LAUNCHERS[@]}"; do
        local src="/usr/share/applications/${app}.desktop"
        [ -f "$src" ] || continue

        pid=$next_pid
        next_pid=$(( next_pid + 1 ))

        mkdir -p "$HOME/.config/xfce4/panel/launcher-${pid}"
        cp "$src" "$HOME/.config/xfce4/panel/launcher-${pid}/${app}.desktop"

        xfconf-query -c xfce4-panel -p "/plugins/plugin-${pid}" \
            --create -t string -s launcher 2>/dev/null || true
        xfconf-query -c xfce4-panel -p "/plugins/plugin-${pid}/items" \
            --create -a -t string -s "${app}.desktop" 2>/dev/null || true

        pids+=( "$pid" )
    done

    # Register the ordered plugin-ids list for panel-2.
    local id_args=()
    for p in "${pids[@]}"; do id_args+=( -t int -s "$p" ); done
    xfconf-query -c xfce4-panel -p /panels/panel-2/plugin-ids \
        --create -a "${id_args[@]}" 2>/dev/null || true

    # Restart the panel process so it picks up the new panel-2 immediately.
    xfce4-panel --restart 2>/dev/null || true
}

setup_dock_panel

# ------------------------------------------------------------------------------
# 4. Mark complete and self-delete autostart entry
# ------------------------------------------------------------------------------
mkdir -p "$(dirname "$MARKER")"
touch "$MARKER"
rm -f "$HOME/.config/autostart/oem-first-run.desktop"

exit 0
