#!/bin/bash
# ==============================================================================
#   Script:       oem-first-run.sh
#   Purpose:      Per-user one-shot. Applies ChromeOS GTK theme, Tela-blue
#                 icons, and the Malta wallpaper to every detected monitor on
#                 first XFCE login, then self-deletes its autostart entry so
#                 the user keeps full freedom over theme/wallpaper afterwards.
#   Installed to: /usr/local/bin/oem-first-run.sh   (mode 755)
#   Installed by: modules/themes.sh
#   Runs as:      the buyer (per user, on first login)
#   Triggered by: skel/.config/autostart/oem-first-run.desktop
#                 (staged into /etc/skel by step_themes)
#   Marker:       ~/.config/.oem-first-run-done  (created at end, checked at start)
#   Reads:        /usr/share/backgrounds/oem-setup/malta.jpg
#                 xfconf-query (xfce4-desktop channel) for monitor list
#   Writes:       xfconf-query: xfce4-desktop ./<monitor>/last-image,
#                                              ./<monitor>/image-style=5
#                 xsettings:    /Net/ThemeName=ChromeOS,
#                               /Net/IconThemeName=Tela-blue
#                 ~/.config/.oem-first-run-done
#                 rm ~/.config/autostart/oem-first-run.desktop
#   Uninstall:    step_uninstall removes the marker, the autostart entry, and
#                 this script itself (per-user cleanup, sub-step 13).
#
#   NOTE: monitor discovery enumerates every `last-image` property xfconf
#   already knows about, falling back to /backdrop/screen0/monitor0/
#   workspace0/last-image when xfdesktop has not yet registered any monitor.
#   This avoids hardcoding monitor names (eDP-1, monitorVirtual1, …) which
#   vary across Chromebook hardware.
# ==============================================================================

MARKER="$HOME/.config/.oem-first-run-done"
[ -f "$MARKER" ] && exit 0

WALLPAPER="/usr/share/backgrounds/oem-setup/malta.jpg"

# --- Wallpaper -----------------------------------------------------------------
# Detect every monitor xfdesktop already knows about and overwrite its
# wallpaper. This avoids guessing the monitor name (eDP-1, monitorVirtual1,
# monitor0, etc.) which varies across Chromebook hardware.
#
# On a brand-new XFCE session, xfdesktop may not have registered any
# last-image property yet. In that case we fall back to a known-good default
# (screen0/monitor0/workspace0) so the wallpaper still applies.
if [ -f "$WALLPAPER" ] && command -v xfconf-query >/dev/null; then
    props=$(xfconf-query -c xfce4-desktop -lv 2>/dev/null \
            | awk '/last-image/ {print $1}')

    if [ -z "$props" ]; then
        props="/backdrop/screen0/monitor0/workspace0/last-image"
    fi

    while read -r prop; do
        [ -z "$prop" ] && continue
        # `--create --type string` makes xfconf-query create the property if
        # it does not yet exist, instead of failing silently.
        xfconf-query -c xfce4-desktop -p "$prop" \
                     -n -t string -s "$WALLPAPER" 2>/dev/null || \
        xfconf-query -c xfce4-desktop -p "$prop" -s "$WALLPAPER" 2>/dev/null
        style_prop="${prop%/last-image}/image-style"
        xfconf-query -c xfce4-desktop -p "$style_prop" \
                     -n -t int -s 5 2>/dev/null || \
        xfconf-query -c xfce4-desktop -p "$style_prop" -s 5 2>/dev/null
    done <<< "$props"
fi

# --- Theme + icons -------------------------------------------------------------
xfconf-query -c xsettings -p /Net/ThemeName     -s "ChromeOS"   2>/dev/null
xfconf-query -c xsettings -p /Net/IconThemeName -s "Tela-blue"  2>/dev/null

# --- Mark complete and self-delete --------------------------------------------
mkdir -p "$(dirname "$MARKER")"
touch "$MARKER"
rm -f "$HOME/.config/autostart/oem-first-run.desktop"

exit 0
