#!/bin/bash
# ==============================================================================
#   Script:       oem-first-run.sh
#   Purpose:      Per-user one-shot. On first XFCE login:
#                   1. Applies the Malta wallpaper to every detected monitor.
#                   2. Moves panel-1 to the top edge, slims it to 24 px,
#                      removes the window-buttons / tasklist plugin (redundant
#                      with Plank's running-app indicators), adds a compact
#                      workspace pager when missing, seeds xfwm4 workspace
#                      defaults (min 4 desks; friendly names when count is 4),
#                      binds Super+Tab (rofi) and Super+Insert (add desk), and strips default
#                      panel launchers (Firefox, XFCE Terminal, Thunar)
#                      so the top bar stays status-only.
#                   3. Seeds a Plank dock at the bottom-centre with pinned
#                      launchers (icon size 40, auto-hide, Matte theme — tuned
#                      for weaker GPUs / small panels), starts plank, and installs a per-user plank
#                      autostart entry so plank comes up on every subsequent
#                      login.
#                 GTK/icon themes are left to distro defaults (no overrides).
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
#                 xfconf-query (xfce4-panel channel) for panel-1/plugin-ids
#                 /usr/share/applications/*.desktop for each pinned launcher
#   Writes:       xfconf-query: xfce4-desktop  ./<monitor>/last-image,
#                                               ./<monitor>/image-style=5
#                 xfconf-query: xfce4-panel     /panels/panel-1/position,
#                                               /panels/panel-1/size,
#                                               /panels/panel-1/plugin-ids
#                                               (+ workspace pager + its prefs),
#                                               (tasklist removed; default launchers
#                                               stripped; empty launcher plugins
#                                               removed + pruned from xfconf)
#                 xfconf-query: xfwm4          /general/workspace_count,
#                                               /general/workspace_names
#                 xfconf-query: xfce4-keyboard-shortcuts  /commands/custom/XF86*
#                                               -> xfdashboard (Chromebook overview)
#                                               /commands/custom/<Super>Insert
#                                               -> oem-add-workspace.sh;
#                                               /commands/custom/<Super>Tab -> rofi
#                                               (if rofi installed)
#                 ~/.config/plank/dock1/settings
#                 ~/.config/plank/dock1/launchers/NN-<name>.dockitem
#                 ~/.config/autostart/plank.desktop
#                 ~/.config/.oem-first-run-done
#                 rm ~/.config/autostart/oem-first-run.desktop
#   Uninstall:    step_uninstall removes the marker, both autostart entries,
#                 the ~/.config/plank tree, and this script (sub-steps 8, 13).
#
#   NOTE: monitor discovery enumerates every `last-image` property xfconf
#   already knows about. If xfdesktop has not written `last-image` yet (common
#   right after login), we derive /backdrop/screen*/monitor*/workspace* bases
#   from other xfconf keys, then fall back to xrandr output names — not
#   `monitor0`, which xfdesktop no longer uses on current Xubuntu (paths look
#   like .../monitoreDP-1/workspace0/last-image).
#
#   NOTE — dock = Plank (NOT a second XFCE panel at the same edge). Xubuntu's
#   primary XFCE panel often occupies one long edge; a second centered XFCE
#   panel on that same edge fights for space. Plank floats as its own
#   composited strip, so it co-exists cleanly with panel-1 while giving a
#   ChromeOS-style centred dock (installed by step_themes).
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

# Ordered list of pinned dock apps (.desktop basename without extension).
# File manager + app store entries are resolved below (Xubuntu/Ubuntu .desktop names).
DOCK_LAUNCHERS=(
    xfce4-appfinder
    oem-workspace-overview
    google-chrome
    xfce4-settings-manager
)

# File manager — first XFCE .desktop that exists
for _oem_fm in thunar org.xfce.thunar; do
    if [ -f "/usr/share/applications/${_oem_fm}.desktop" ]; then
        DOCK_LAUNCHERS+=( "$_oem_fm" )
        break
    fi
done

# Software centre — Xubuntu/Ubuntu-prioritised candidates (skip if none installed)
_oem_store_candidates=(
    snap-store ubuntu-software org.gnome.Software gnome-software synaptic software-properties-gtk
)
for _oem_store in "${_oem_store_candidates[@]}"; do
    if [ -f "/usr/share/applications/${_oem_store}.desktop" ]; then
        DOCK_LAUNCHERS+=( "$_oem_store" )
        break
    fi
done

DOCK_LAUNCHERS+=(
    vlc
    Zoom
    Gmail
    GoogleDocs
    GoogleSheets
    GoogleSlides
    GoogleDrive
    Gemini
    YouTube
    Spotify
)

# ------------------------------------------------------------------------------
# 1. Wallpaper
# Detect every monitor xfdesktop already knows about and overwrite its
# wallpaper. When `last-image` keys do not exist yet, discover real monitor
# paths (RandR names) — not legacy `monitor0`, which xfdesktop ignores.
# ------------------------------------------------------------------------------
if [ -f "$WALLPAPER" ] && command -v xfconf-query >/dev/null; then
    _oem_xfce_set_backdrop_last_image() {
        local prop="$1" style_prop="${1%/last-image}/image-style"
        xfconf-query -c xfce4-desktop -p "$prop" \
                     -n -t string -s "$WALLPAPER" 2>/dev/null || \
        xfconf-query -c xfce4-desktop -p "$prop" -s "$WALLPAPER" 2>/dev/null
        xfconf-query -c xfce4-desktop -p "$style_prop" \
                     -n -t int -s 5 2>/dev/null || \
        xfconf-query -c xfce4-desktop -p "$style_prop" -s 5 2>/dev/null
    }

    props=$(xfconf-query -c xfce4-desktop -lv 2>/dev/null \
            | awk '/last-image/ {print $1}')

    if [ -n "$props" ]; then
        while read -r prop; do
            [ -z "$prop" ] && continue
            _oem_xfce_set_backdrop_last_image "$prop"
        done <<< "$props"
    else
        # xfdesktop registered backdrop prefs but no last-image yet — reuse
        # monitor/workspace paths from other channel keys.
        backdrop_bases=$(xfconf-query -c xfce4-desktop -l 2>/dev/null \
            | grep -oE '^/backdrop/screen[0-9]+/monitor[^/]+/workspace[0-9]+' \
            | sort -u)
        if [ -n "$backdrop_bases" ]; then
            while read -r base; do
                [ -z "$base" ] && continue
                _oem_xfce_set_backdrop_last_image "${base}/last-image"
            done <<< "$backdrop_bases"
        elif command -v xrandr >/dev/null && [ -n "${DISPLAY:-}" ]; then
            while read -r out; do
                [ -z "$out" ] && continue
                _oem_xfce_set_backdrop_last_image \
                    "/backdrop/screen0/monitor${out}/workspace0/last-image"
            done < <(xrandr --query 2>/dev/null | awk '$2 == "connected" {print $1}')
        else
            _oem_xfce_set_backdrop_last_image \
                "/backdrop/screen0/monitor0/workspace0/last-image"
        fi
    fi
    unset -f _oem_xfce_set_backdrop_last_image
fi

# ------------------------------------------------------------------------------
# 2. Panel-1 — move to top, slim to 24 px, strip tasklist + default launchers,
#    ensure a workspace pager.
#
# Xubuntu may ship panel-1 at top or bottom. We move panel-1 to the top edge so
# it acts as a slim status bar (Whisker Menu,
# clock, tray, volume, power) while Plank owns the bottom as the dock. The
# window-buttons / tasklist plugin is removed because Plank already shows
# running-app indicators. A missing **pager** plugin is inserted after the first
# panel item so users always see workspace dots on the top bar.
#
# Default quick-launch icons (Firefox, XFCE Terminal, Thunar) are stored by XFCE
# as .desktop files under ~/.config/xfce4/panel/launcher-<plugin-id>/. Those
# entries are removed so the top bar does not duplicate Plank pins (Thunar is
# on the dock). Launcher plugins with no items left are dropped from panel-1
# and pruned from xfconf (/plugins/plugin-<id>).
#
# Position string encoding (XFCE GravityType):
#   p=6  = top-left (NW_H) — default for a top horizontal panel.
#   p=2  = top-center (N)  — fallback if the panel appears off-screen.
# Both are tried for robustness across Xfce versions.
#
# Plugin discovery: XFCE allocates plugin IDs at install time and they differ
# across machines, so we enumerate /panels/panel-1/plugin-ids, look up each
# plugin's type, delete matching launcher .desktop files, filter out
# tasklist / window-buttons, drop empty launcher plugins, then write back.
# ------------------------------------------------------------------------------

# Returns 0 if this launcher-item .desktop should be removed from panel-1.
panel_launcher_desktop_should_strip() {
    local f="$1" bn line val first
    [ -f "$f" ] || return 1

    bn=$(basename "$f" | tr '[:upper:]' '[:lower:]')
    case "$bn" in
        firefox.desktop|firefox-esr.desktop)          return 0 ;;
        thunar.desktop|org.xfce.thunar.desktop)       return 0 ;;
        xfce4-terminal.desktop|xfce4-terminal-emulator.desktop) return 0 ;;
    esac

    line=$(LC_ALL=C grep -m1 '^Exec=' "$f" 2>/dev/null || true)
    [ -n "$line" ] || return 1
    val=${line#Exec=}
    read -r first _ <<< "$val"
    first=${first%/}
    first=${first##*/}
    case "$first" in
        firefox|firefox-esr|thunar|xfce4-terminal) return 0 ;;
    esac

    # Non-standard filenames: distro .desktop may use argv0 (optional path prefix).
    if echo "$line" | grep -Eiq '^Exec=([^[:space:]]*/)?(firefox-esr|firefox|thunar|xfce4-terminal)([[:space:]]|%|$)' ; then
        return 0
    fi
    return 1
}

# ------------------------------------------------------------------------------
# Workspace defaults — minimum desk count + friendly names (xfwm4).
# ------------------------------------------------------------------------------
setup_workspace_defaults() {
    command -v xfconf-query >/dev/null || return 0

    local cur
    cur=$(xfconf-query -c xfwm4 -p /general/workspace_count -v 2>/dev/null || echo "")
    if ! [[ "${cur:-0}" =~ ^[0-9]+$ ]]; then cur=1; fi

    if [ "$cur" -lt 4 ]; then
        xfconf-query -c xfwm4 -p /general/workspace_count -n -t int -s 4 2>/dev/null || \
        xfconf-query -c xfwm4 -p /general/workspace_count -s 4 2>/dev/null || true
        cur=4
    fi

    cur=$(xfconf-query -c xfwm4 -p /general/workspace_count -v 2>/dev/null || echo 4)
    [[ "$cur" =~ ^[0-9]+$ ]] || cur=4

    if [ "$cur" -eq 4 ]; then
        xfconf-query -c xfwm4 -p /general/workspace_names -r 2>/dev/null || true
        xfconf-query -c xfwm4 -p /general/workspace_names -n \
            -t string -s "Web" -t string -s "Work" -t string -s "Media" -t string -s "Misc" \
            2>/dev/null || \
        xfconf-query -c xfwm4 -p /general/workspace_names \
            -t string -s "Web" -t string -s "Work" -t string -s "Media" -t string -s "Misc" \
            2>/dev/null || true
    fi
}

# Largest numeric xfce4-panel plugin-* id (for allocating a new plugin id).
_oem_panel_max_plugin_id() {
    xfconf-query -c xfce4-panel -lv 2>/dev/null \
        | grep -o '/plugins/plugin-[0-9][0-9]*' \
        | grep -o '[0-9][0-9]*' \
        | sort -n | tail -1
}

# Compact pager settings for a 24 px panel (numbered workspaces, single row).
_oem_configure_panel_pager() {
    local pid="$1"
    xfconf-query -c xfce4-panel -p "/plugins/plugin-${pid}/rows" -n -t uint -s 1 2>/dev/null || \
        xfconf-query -c xfce4-panel -p "/plugins/plugin-${pid}/rows" -s 1 2>/dev/null || true
    xfconf-query -c xfce4-panel -p "/plugins/plugin-${pid}/wrap-workspaces" \
        -n -t bool -s true 2>/dev/null || \
        xfconf-query -c xfce4-panel -p "/plugins/plugin-${pid}/wrap-workspaces" -s true 2>/dev/null || true
    xfconf-query -c xfce4-panel -p "/plugins/plugin-${pid}/workspace-scrolling" \
        -n -t bool -s true 2>/dev/null || \
        xfconf-query -c xfce4-panel -p "/plugins/plugin-${pid}/workspace-scrolling" -s true 2>/dev/null || true
    xfconf-query -c xfce4-panel -p "/plugins/plugin-${pid}/miniature-view" \
        -n -t bool -s false 2>/dev/null || \
        xfconf-query -c xfce4-panel -p "/plugins/plugin-${pid}/miniature-view" -s false 2>/dev/null || true
}

# Ensure panel-1 has a workspace pager; insert after first plugin if added.
_oem_ensure_panel_pager() {
    local ids=( "$@" ) pid has_pager="" pager_id=""
    for pid in "${ids[@]}"; do
        [ "$(xfconf-query -c xfce4-panel -p "/plugins/plugin-${pid}" 2>/dev/null)" = pager ] \
            || continue
        has_pager=1
        pager_id=$pid
        break
    done
    if [ -n "$has_pager" ]; then
        _oem_configure_panel_pager "$pager_id"
        return 0
    fi

    local max new_id
    max=$(_oem_panel_max_plugin_id)
    max=${max:-0}
    new_id=$((max + 1))

    xfconf-query -c xfce4-panel -p "/plugins/plugin-${new_id}" -n -t string -s pager 2>/dev/null || \
        xfconf-query -c xfce4-panel -p "/plugins/plugin-${new_id}" -s pager 2>/dev/null || true
    _oem_configure_panel_pager "$new_id"

    local out=()
    out=( "${ids[0]}" "$new_id" "${ids[@]:1}" )
    local id_args=()
    for pid in "${out[@]}"; do id_args+=( -t int -s "$pid" ); done
    xfconf-query -c xfce4-panel \
        -p /panels/panel-1/plugin-ids -a "${id_args[@]}" 2>/dev/null || true
}

setup_top_panel() {
    command -v xfconf-query >/dev/null || return 0

    # Move panel-1 to the top edge (p=6 = top-left; try p=2 as fallback).
    xfconf-query -c xfce4-panel -p /panels/panel-1/position \
        -s "p=6;x=0;y=0" 2>/dev/null || true

    # Slim the height to 24 px (stock Xubuntu panel is often taller).
    xfconf-query -c xfce4-panel -p /panels/panel-1/size \
        -t uint -s 24 2>/dev/null || true

    # Read current plugin-ids for panel-1 (one integer per line).
    local current_ids=()
    mapfile -t current_ids < <(
        xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids 2>/dev/null \
        | grep -E '^[0-9]+$' || true
    )

    if [ ${#current_ids[@]} -eq 0 ]; then
        xfce4-panel --restart 2>/dev/null || true
        return 0
    fi

    local pid ptype ldir f remove_plugin_ids=()
    for pid in "${current_ids[@]}"; do
        ptype=$(xfconf-query -c xfce4-panel \
                    -p "/plugins/plugin-${pid}" 2>/dev/null || true)
        if [ "$ptype" = launcher ]; then
            ldir="$HOME/.config/xfce4/panel/launcher-$pid"
            if [ -d "$ldir" ]; then
                shopt -s nullglob
                for f in "$ldir"/*.desktop; do
                    if panel_launcher_desktop_should_strip "$f"; then
                        rm -f "$f"
                    fi
                done
                shopt -u nullglob
            fi
        fi
    done

    local new_ids=() remaining
    for pid in "${current_ids[@]}"; do
        ptype=$(xfconf-query -c xfce4-panel \
                    -p "/plugins/plugin-${pid}" 2>/dev/null || true)
        case "$ptype" in
            tasklist|window-buttons) ;;
            launcher)
                ldir="$HOME/.config/xfce4/panel/launcher-$pid"
                if [ ! -d "$ldir" ]; then
                    new_ids+=( "$pid" )
                else
                    shopt -s nullglob
                    remaining=( "$ldir"/*.desktop )
                    shopt -u nullglob
                    if [ ${#remaining[@]} -eq 0 ]; then
                        remove_plugin_ids+=( "$pid" )
                    else
                        new_ids+=( "$pid" )
                    fi
                fi
                ;;
            *) new_ids+=( "$pid" ) ;;
        esac
    done

    local changed=false _i
    if [ ${#new_ids[@]} -ne ${#current_ids[@]} ]; then
        changed=true
    else
        for _i in "${!current_ids[@]}"; do
            if [ "${current_ids[$_i]}" != "${new_ids[$_i]}" ]; then
                changed=true
                break
            fi
        done
    fi

    if [ "$changed" = true ] && [ ${#new_ids[@]} -gt 0 ]; then
        local id_args=()
        for pid in "${new_ids[@]}"; do id_args+=( -t int -s "$pid" ); done
        xfconf-query -c xfce4-panel \
            -p /panels/panel-1/plugin-ids -a "${id_args[@]}" 2>/dev/null || true
        for pid in "${remove_plugin_ids[@]}"; do
            xfconf-query -c xfce4-panel \
                -p "/plugins/plugin-${pid}" -r -R 2>/dev/null || true
        done
    fi

    mapfile -t panel_plugins < <(
        xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids 2>/dev/null \
        | grep -E '^[0-9]+$' || true
    )
    if [ ${#panel_plugins[@]} -gt 0 ]; then
        _oem_ensure_panel_pager "${panel_plugins[@]}"
    fi

    xfce4-panel --restart 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# 2b. Chromebook top-row “overview / scale” → xfdashboard
#
# cros-keyboard-map (keyd) leaves the Vivaldi “scale” key as XF86Scale (and
# similar XF86* codes on some boards). XFCE does not map those to an overview
# by default — bind common keys to the same binary as Plank + libinput-gestures.
# If a device uses a different keysym, run `xev`, note the KeyPress name, and
# add a /commands/custom/<keysym> line below.
# ------------------------------------------------------------------------------
setup_workspace_overview_keys() {
    command -v xfconf-query >/dev/null || return 0
    command -v xfdashboard >/dev/null 2>&1 || return 0

    bind_xfdashboard_keysym() {
        local keysym="$1"
        local prop="/commands/custom/${keysym}"
        xfconf-query -c xfce4-keyboard-shortcuts \
            -p "$prop" -n -t string -s "xfdashboard" 2>/dev/null || \
        xfconf-query -c xfce4-keyboard-shortcuts \
            -p "$prop" -s "xfdashboard" 2>/dev/null || true
    }

    bind_xfdashboard_keysym "XF86Scale"
    bind_xfdashboard_keysym "XF86LaunchA"
    bind_xfdashboard_keysym "XF86Explorer"
}

# ------------------------------------------------------------------------------
# 2c. Super+Insert → add virtual workspace (oem-add-workspace.sh from gestures).
# ------------------------------------------------------------------------------
setup_add_workspace_key() {
    command -v xfconf-query >/dev/null || return 0
    [ -x /usr/local/bin/oem-add-workspace.sh ] || return 0

    local prop="/commands/custom/<Super>Insert"
    # Full path: libinput-gestures invokes binaries with no shell.
    xfconf-query -c xfce4-keyboard-shortcuts \
        -p "$prop" -n -t string -s "/usr/local/bin/oem-add-workspace.sh" 2>/dev/null || \
    xfconf-query -c xfce4-keyboard-shortcuts \
        -p "$prop" -s "/usr/local/bin/oem-add-workspace.sh" 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# 2d. Super+Tab → rofi window list (if installed).
# ------------------------------------------------------------------------------
setup_rofi_window_switcher() {
    command -v xfconf-query >/dev/null || return 0
    command -v rofi >/dev/null 2>&1 || return 0

    local prop="/commands/custom/<Super>Tab"
    local cmd='/bin/sh -c "/usr/bin/rofi -show window -show-icons"'
    xfconf-query -c xfce4-keyboard-shortcuts \
        -p "$prop" -n -t string -s "$cmd" 2>/dev/null || \
    xfconf-query -c xfce4-keyboard-shortcuts \
        -p "$prop" -s "$cmd" 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# 3. Theme defaults (ChromeOS-like UI)
# ------------------------------------------------------------------------------
setup_theme_defaults() {
    command -v xfconf-query >/dev/null || return 0

    local gtk_theme=""
    for t in "ChromeOS-Dark" "ChromeOS-dark" "ChromeOS"; do
        if [ -d "/usr/share/themes/$t" ]; then
            gtk_theme="$t"
            break
        fi
    done

    if [ -n "$gtk_theme" ]; then
        xfconf-query -c xsettings -p /Net/ThemeName -n -t string -s "$gtk_theme" 2>/dev/null || \
        xfconf-query -c xsettings -p /Net/ThemeName -s "$gtk_theme" 2>/dev/null || true
        
        xfconf-query -c xfwm4 -p /general/theme -n -t string -s "$gtk_theme" 2>/dev/null || \
        xfconf-query -c xfwm4 -p /general/theme -s "$gtk_theme" 2>/dev/null || true
    fi

    local icon_theme=""
    for i in "Tela-dark" "Tela-circle-dark" "Tela"; do
        if [ -d "/usr/share/icons/$i" ]; then
            icon_theme="$i"
            break
        fi
    done

    if [ -n "$icon_theme" ]; then
        xfconf-query -c xsettings -p /Net/IconThemeName -n -t string -s "$icon_theme" 2>/dev/null || \
        xfconf-query -c xsettings -p /Net/IconThemeName -s "$icon_theme" 2>/dev/null || true
    fi
}

# ------------------------------------------------------------------------------
# 4. Plank dock (bottom-centre, auto-hide, pinned launchers).
# Plank reads dockitem files from ~/.config/plank/dock1/launchers/ in
# lexicographic filename order, so we prefix each file with a zero-padded
# index (01-, 02-, …) to lock the order specified in DOCK_LAUNCHERS.
# ------------------------------------------------------------------------------
setup_plank_dock() {
    command -v plank >/dev/null || return 0

    local plank_dir="$HOME/.config/plank/dock1"
    local launchers_dir="$plank_dir/launchers"
    mkdir -p "$launchers_dir"

    # Settings (lighter redraw + smoother hide/show on composited desktops):
    #   Position=3       Gtk.PositionType.BOTTOM
    #   Alignment=3      PlankItemsAlignment.CENTER
    #   HideMode=2       HideType AUTOHIDE (hide until cursor hits dock edge — frees vertical space)
    #   HideDelay/UnhideDelay  small nonzero ms — reduces twitchy overlap flaps at launch/maximize
    #   IconSize=40      modest GPU win vs 48 px; tighter strip on laptops
    #   Theme=Matte      ships with plank; less translucent work than Transparent
    #   LockItems=false  buyer can drag-rearrange after purchase
    cat > "$plank_dir/settings" <<'EOF'
[PlankDockPreferences]
CurrentWorkspaceOnly=false
IconSize=40
HideMode=2
UnhideDelay=150
HideDelay=150
Monitor=
DockItems=
Position=3
Offset=0
Theme=Matte
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

setup_workspace_defaults
setup_top_panel
setup_workspace_overview_keys
setup_add_workspace_key
setup_rofi_window_switcher
setup_theme_defaults
setup_plank_dock

# ------------------------------------------------------------------------------
# 5. Mark complete and self-delete autostart entry
# ------------------------------------------------------------------------------
mkdir -p "$(dirname "$MARKER")"
touch "$MARKER"
rm -f "$HOME/.config/autostart/oem-first-run.desktop"

exit 0
