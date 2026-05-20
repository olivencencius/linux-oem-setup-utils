#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/var/lib/xubuntu-oem-setup}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/.state}"
MODULE_ID="10_web_apps"

is_done() { [ -f "$STATE_FILE" ] && grep -qxF "$MODULE_ID" "$STATE_FILE"; }
mark_done() { mkdir -p "$STATE_DIR"; grep -qxF "$MODULE_ID" "$STATE_FILE" || echo "$MODULE_ID" >> "$STATE_FILE"; }

if is_done; then
    echo "[${MODULE_ID}] Already completed — skipping."
    exit 0
fi

CHROME_BIN="/usr/bin/google-chrome-stable"
if [ ! -x "$CHROME_BIN" ]; then
    CHROME_BIN="$(command -v google-chrome-stable || true)"
fi
if [ -z "$CHROME_BIN" ]; then
    echo "[!] google-chrome-stable not found. Run module 08_install_chrome.sh first." >&2
    exit 1
fi

APP_DST="/usr/share/applications"
CHROME_FLAGS="--password-store=basic"

# Point directly to your GitHub repository's raw asset folder
ICON_BASE_URL="https://raw.githubusercontent.com/olivencencius/linux-oem-setup-utils/main/assets/icons"

write_webapp() {
    local name="$1"
    local url="$2"
    local label="$3"
    
    local desktop="${APP_DST}/webapp-${name}.desktop"
    local icon_path="/usr/share/pixmaps/webapp-${name}.svg"

    # Download the SVG icon from your GitHub repo if it's not already on the machine
    if [ ! -f "$icon_path" ]; then
        wget -q --show-progress -O "$icon_path" "${ICON_BASE_URL}/${name}.svg" || true
    fi

    cat > "$desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=${label}
Comment=${label} (web app)
Exec=${CHROME_BIN} ${CHROME_FLAGS} --app=${url}
Icon=${icon_path}
Terminal=false
Categories=Network;
StartupNotify=true
EOF
    echo "    [+] ${name}.desktop (with local SVG)"
}

echo "--> Creating system-wide Chrome web app launchers with self-hosted SVG icons…"

# The first argument must match the exact name of the .svg file in your assets/icons folder
write_webapp "zoom"                  "https://app.zoom.us/wc/home"             "Zoom"
write_webapp "netflix"               "https://www.netflix.com"                 "Netflix"
write_webapp "spotify"               "https://open.spotify.com" "Spotify"
write_webapp "gmail"                 "https://mail.google.com"                 "Gmail"
write_webapp "gemini"                "https://gemini.google.com"               "Gemini"
write_webapp "youtube"               "https://www.youtube.com"                 "YouTube"
write_webapp "primevideo"            "https://www.primevideo.com"              "Prime Video"
write_webapp "disneyplus"            "https://www.disneyplus.com"              "Disney+"
write_webapp "hbomax"                "https://play.max.com"                    "Max"
write_webapp "chrome-remote-desktop" "https://remotedesktop.google.com/access" "Chrome Remote Desktop"
write_webapp "googledocs"            "https://docs.google.com"                 "Google Docs"
write_webapp "googlesheets"          "https://sheets.google.com"               "Google Sheets"
write_webapp "googleslides"          "https://slides.google.com"               "Google Slides"
write_webapp "googledrive"           "https://drive.google.com"                "Google Drive"

update-desktop-database "$APP_DST" 2>/dev/null || true

mark_done
echo "[${MODULE_ID}] Done."