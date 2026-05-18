#!/bin/bash
# ==============================================================================
#   Ad-hoc: sync OEM toolkit defaults into every normal user's home.
#
#   Use when extra accounts were created before step_themes, or skel was
#   incomplete — fixes missing oem-first-run autostart, bracketed-paste inputrc,
#   and (optional) resets first-run markers so XFCE layout reapplies on login.
#
#   Run from your main account (must use sudo):
#     sudo bash /path/to/linux-oem-setup-utils/assets/scripts/oem-sync-all-user-homes.sh
#     wget -qO- https://raw.githubusercontent.com/olivencencius/linux-oem-setup-utils/main/assets/scripts/oem-sync-all-user-homes.sh | sudo bash -s -- --reset
#
#   --reset   Remove ~/.config/.oem-first-run-done for each user and reinstall
#             oem-first-run autostart so the next login runs the full script.
#   --dry-run Print what would happen; make no changes.
#   --strict  Exit 1 if wallpaper / Plank / oem-first-run / web apps / games /
#             dock-related .desktop files are not all present (see preflight).
#
#   Source for oem-first-run.desktop: /etc/skel (if missing, same file from
#   repo skel/ next to this script).
# ==============================================================================

set -euo pipefail

if [ "${EUID:-}" -ne 0 ]; then
    echo "oem-sync-all-user-homes: run as root (sudo bash \"$0\" …)" >&2
    exit 1
fi

RESET=false
DRY=false
STRICT=false
for a in "$@"; do
    case "$a" in
        --reset)   RESET=true ;;
        --dry-run) DRY=true ;;
        --strict)  STRICT=true ;;
        -h|--help)
            sed -n '1,30p' "$0" | tail -n +2
            exit 0
            ;;
        *)
            echo "Unknown option: $a (use --help)" >&2
            exit 2
            ;;
    esac
done

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_SKEL="$SCRIPT_DIR/../../skel"
INPUTRC_LINE='set enable-bracketed-paste off'

_oem_has_desktop() {
    [ -f "/usr/share/applications/${1}.desktop" ]
}

_oem_has_any_game_desktop() {
    local d
    for d in "$@"; do
        _oem_has_desktop "$d" && return 0
    done
    return 1
}

# Align checks with pipeline: themes (wallpaper, Plank, oem-first-run), web_apps (13),
# apps (VLC + games), gestures (workspace overview .desktop).
_oem_preflight_system_payload() {
    local issues=0

    echo "==> Preflight (wallpaper · web apps · games · dock prerequisites)"

    if [ ! -x /usr/local/bin/oem-first-run.sh ]; then
        echo "    [!] FATAL: /usr/local/bin/oem-first-run.sh missing — run menu 1 or 9 (themes)." >&2
        exit 1
    fi
    echo "    [ok] oem-first-run.sh"

    if [ ! -f /usr/share/backgrounds/oem-setup/malta.jpg ]; then
        echo "    [!] MISSING: Malta wallpaper — run menu 1 or 9 (themes)." >&2
        issues=$((issues + 1))
    else
        echo "    [ok] Malta wallpaper"
    fi

    if ! command -v plank &>/dev/null; then
        echo "    [!] MISSING: Plank binary — run menu 1 or 9 (themes)." >&2
        issues=$((issues + 1))
    else
        echo "    [ok] Plank"
    fi

    if ! _oem_has_desktop google-chrome; then
        echo "    [!] MISSING: google-chrome desktop — run menu 5 (Chrome)." >&2
        issues=$((issues + 1))
    else
        echo "    [ok] Google Chrome launcher"
    fi

    if _oem_has_desktop Zoom; then
        echo "    [ok] Zoom launcher (dock pin)"
    else
        echo "    [i] Zoom launcher missing — dock skips that pin (optional; menu 6 / network)."
    fi

    local web_apps=(
        Netflix PrimeVideo DisneyPlus HBOMax Spotify YouTube
        Gmail GoogleDocs GoogleSheets GoogleSlides GoogleDrive Gemini ChromeRemoteDesktop
    )
    local app web_ok=0
    for app in "${web_apps[@]}"; do
        _oem_has_desktop "$app" && web_ok=$((web_ok + 1))
    done
    if [ "$web_ok" -ne 13 ]; then
        echo "    [!] WEB APPS: ${web_ok}/13 .desktop files — run menu 8 (web apps)." >&2
        issues=$((issues + 1))
    else
        echo "    [ok] 13/13 web-app shortcuts"
    fi

    if ! _oem_has_desktop vlc; then
        echo "    [!] MISSING: vlc — run menu 7 (apps)." >&2
        issues=$((issues + 1))
    else
        echo "    [ok] VLC"
    fi

    local g
    for g in supertuxkart; do
        if ! _oem_has_desktop "$g"; then
            echo "    [!] MISSING: $g — run menu 7 (apps)." >&2
            issues=$((issues + 1))
        fi
    done
    if ! _oem_has_desktop quadrapassel && ! _oem_has_desktop org.gnome.Quadrapassel; then
        echo "    [!] MISSING: quadrapassel launcher — run menu 7 (apps)." >&2
        issues=$((issues + 1))
    fi
    if _oem_has_desktop supertuxkart \
        && { _oem_has_desktop quadrapassel || _oem_has_desktop org.gnome.Quadrapassel; }; then
        echo "    [ok] SuperTuxKart + Quadrapassel launchers"
    fi
    if ! _oem_has_any_game_desktop aisleriot org.gnome.Aisleriot sol; then
        echo "    [!] MISSING: Aisleriot-style game launcher — run menu 7 (apps)." >&2
        issues=$((issues + 1))
    else
        echo "    [ok] Aisleriot/solitaire launcher"
    fi

    if ! _oem_has_desktop oem-workspace-overview; then
        echo "    [!] MISSING: oem-workspace-overview — run menu 9 or 11 (gestures)." >&2
        issues=$((issues + 1))
    else
        echo "    [ok] Workspace overview launcher (dock pin)"
    fi

    echo ""
    if [ "$issues" -gt 0 ]; then
        echo "    [!] $issues preflight problem(s) — dock/wallpaper may be incomplete until you re-run those menu steps." >&2
        if $STRICT; then
            echo "oem-sync-all-user-homes: --strict aborting." >&2
            exit 1
        fi
    else
        echo "    [ok] System payload matches toolkit expectations for wallpaper, web apps, games, dock pins."
    fi
    echo ""
}

oem_first_run_src() {
    local s="/etc/skel/.config/autostart/oem-first-run.desktop"
    if [ -f "$s" ]; then
        echo "$s"
        return 0
    fi
    s="$REPO_SKEL/.config/autostart/oem-first-run.desktop"
    if [ -f "$s" ]; then
        echo "$s"
        return 0
    fi
    echo ""
    return 1
}

run() {
    if $DRY; then
        echo "[dry-run] $*"
    else
        "$@"
    fi
}

_oem_preflight_system_payload

src_file=$(oem_first_run_src) || src_file=""

if [ -z "$src_file" ]; then
    echo "[!] Cannot find oem-first-run.desktop in /etc/skel or $REPO_SKEL" >&2
    echo "    Run step_themes once (menu 9) or clone the repo so skel/ exists." >&2
    exit 1
fi

echo "==> oem-sync-all-user-homes (RESET=$RESET DRY=$DRY STRICT=$STRICT)"
echo "    Autostart source: $src_file"

has_input_group=false
getent group input &>/dev/null && has_input_group=true

while IFS=: read -r u _ uid _ _ home _; do
    [ "$uid" -ge 1000 ] 2>/dev/null || continue
    [ "$uid" -lt 65534 ] 2>/dev/null || continue
    [ -n "${home:-}" ] && [ -d "$home" ] || continue

    marker="$home/.config/.oem-first-run-done"

    if $RESET; then
        if [ -f "$marker" ]; then
            run rm -f "$marker"
            echo "    [-] removed marker → ~$u"
        fi
    fi

    if ! $RESET && [ -f "$marker" ]; then
        echo "    [.] skip autostart ~$u (first-run already done)"
    else
        run install -d -m 755 -o "$u" -g "$u" "$home/.config/autostart"
        run install -m 644 -o "$u" -g "$u" "$src_file" "$home/.config/autostart/oem-first-run.desktop"
        echo "    [+] oem-first-run.desktop → ~$u (uid $uid)"
    fi

    if ! grep -qxF "$INPUTRC_LINE" "$home/.inputrc" 2>/dev/null; then
        if $DRY; then
            echo "[dry-run] append inputrc line → ~$u"
        else
            touch "$home/.inputrc"
            echo "$INPUTRC_LINE" >>"$home/.inputrc"
            chown "$u:$u" "$home/.inputrc"
        fi
        echo "    [+] ~/.inputrc bracketed-paste → ~$u"
    fi

    if $has_input_group; then
        if id -nG "$u" 2>/dev/null | tr ' ' '\n' | grep -qx input; then
            :
        else
            run usermod -a -G input "$u"
            echo "    [+] usermod -aG input → $u"
        fi
    fi
done < /etc/passwd

if ! $has_input_group; then
    echo "    [!] group 'input' missing — libinput-gestures may not work until installed." >&2
fi

echo ""
echo "==> Done. Each user should log out and log back into XFCE once (or reboot)."
if $RESET; then
    echo "    (--reset) oem-first-run.sh will replay wallpaper, panel, and Plank on next login."
fi
