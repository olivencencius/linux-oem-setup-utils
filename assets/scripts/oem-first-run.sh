#!/bin/bash
# ==============================================================================
#   Script:       oem-first-run.sh
#   Purpose:      Per-user one-shot. On first XFCE login:
#                   1. Applies the Malta wallpaper to every detected monitor.
#                   2. Sets Mint-Y-Aqua GTK theme + Papirus icons via xsettings
#                      and xfwm4 (window decorations).
#                   3. Seeds a Plank dock at the bottom-centre with 11 pinned
#                      launchers (icon size 48, intelligent hide, Transparent
#                      theme), starts plank, and installs a per-user plank
#                      autostart entry so plank comes up on every subsequent
#                      login.
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
#                 /usr/share/applications/*.desktop for each pinned launcher
#   Writes:       xfconf-query: xfce4-desktop  ./<monitor>/last-image,
#                                               ./<monitor>/image-style=5
#                 xfconf-query: xsettings       /Net/ThemeName=Mint-Y-Aqua
#                                               /Net/IconThemeName=Papirus
#                 xfconf-query: xfwm4           /general/theme=Mint-Y-Aqua
#                 ~/.config/plank/dock1/settings
#                 ~/.config/plank/dock1/launchers/NN-<name>.dockitem (× 11)
#                 ~/.config/autostart/plank.desktop
#                 ~/.config/.oem-first-run-done
#                 rm ~/.config/autostart/oem-first-run.desktop
#   Uninstall:    step_uninstall removes the marker, both autostart entries,
#                 the ~/.config/plank tree, and this script (sub-steps 8, 13).
#
#   NOTE: monitor discovery enumerates every `last-image` property xfconf
#   already knows about, falling back to /backdrop/screen0/monitor0/
#   workspace0/last-image when xfdesktop has not yet registered any monitor.
#   This avoids hardcoding monitor names (eDP-1, monitorVirtual1, …) which
#   vary across Chromebook hardware.
#
#   NOTE — dock = Plank (NOT a second XFCE panel). Mint XFCE already owns the
#   bottom screen edge with panel-1 (mint-menu + window list + tray), so
#   trying to add a second "centred" XFCE panel at the same edge fails or
#   collides. Plank floats above the screen as its own window, so it
#   co-exists with Mint's panel-1 cleanly. Plank is a one-package apt
#   dependency installed by step_themes and is the simplest reliable way to
#   render a ChromeOS-style centred dock on Mint XFCE.
#
#   NOTE — idempotency. We deliberately do NOT short-circuit if the plank
#   config dir already exists: if a previous run failed half-way (e.g.
#   apt-get got interrupted before plank was installed), re-running this
#   script should re-seed cleanly. The dockitem writes use heredoc-overwrite
#   so they are safe to repeat.
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
# 3. Plank dock (bottom-centre, intelligent hide, 11 pinned launchers).
# Plank reads dockitem files from ~/.config/plank/dock1/launchers/ in
# lexicographic filename order, so we prefix each file with a zero-padded
# index (01-, 02-, … 11-) to lock the order specified in DOCK_LAUNCHERS.
# ------------------------------------------------------------------------------
setup_plank_dock() {
    command -v plank >/dev/null || return 0

    local plank_dir="$HOME/.config/plank/dock1"
    local launchers_dir="$plank_dir/launchers"
    mkdir -p "$launchers_dir"

    # Settings:
    #   Position=3       Gtk.PositionType.BOTTOM
    #   Alignment=3      PlankItemsAlignment.CENTER
    #   HideMode=1       PlankHideType.INTELLIGENT (hide only when a window overlaps)
    #   IconSize=48      48 px (matches Mint XFCE panel-1 height)
    #   Theme=Transparent  ships with plank; cleanest ChromeOS-like look
    #   LockItems=false  buyer can drag-rearrange after purchase
    cat > "$plank_dir/settings" <<'EOF'
[PlankDockPreferences]
CurrentWorkspaceOnly=false
IconSize=48
HideMode=1
UnhideDelay=0
HideDelay=0
Monitor=
DockItems=
Position=3
Offset=0
Theme=Transparent
Alignment=3
ItemsAlignment=3
LockItems=false
PressureReveal=false
PinnedOnly=false
AutoPinning=true
ShowDockItem=false
ZoomEnabled=false
ZoomPercent=150
EOF

    # Emit one dockitem per launcher whose backing .desktop actually exists.
    # Silent-skip preserves the existing safety net (e.g. Zoom .deb download
    # failed → step_zoom returns 0 → no Zoom.desktop → Plank just renders 10).
    local idx=1 app src n
    for app in "${DOCK_LAUNCHERS[@]}"; do
        src="/usr/share/applications/${app}.desktop"
        [ -f "$src" ] || continue
        n=$(printf '%02d' "$idx")
        cat > "$launchers_dir/${n}-${app}.dockitem" <<EOF
[PlankDockItemPreferences]
Launcher=file://${src}
EOF
        idx=$(( idx + 1 ))
    done

    # Install a per-user plank autostart entry so plank comes up on every
    # subsequent login. We write it here (not via /etc/skel) so the
    # first-login race against this script is impossible: by the time
    # plank.desktop exists, the dock config is already in place.
    mkdir -p "$HOME/.config/autostart"
    cat > "$HOME/.config/autostart/plank.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Plank
Comment=ChromeOS-style dock
Exec=plank
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    # Start plank now so the live session (and the first-login buyer) sees
    # the dock immediately. If plank is already running it just no-ops
    # because plank holds a single-instance dbus lock.
    if ! pgrep -x plank >/dev/null 2>&1; then
        (plank >/dev/null 2>&1 &) || true
    fi
}

setup_plank_dock

# ------------------------------------------------------------------------------
# 4. Mark complete and self-delete autostart entry
# ------------------------------------------------------------------------------
mkdir -p "$(dirname "$MARKER")"
touch "$MARKER"
rm -f "$HOME/.config/autostart/oem-first-run.desktop"

exit 0
