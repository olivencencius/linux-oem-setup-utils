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

write_webapp() {
    local name="$1"
    local url="$2"
    local label="$3"
    local desktop="${APP_DST}/${name}.desktop"

    cat > "$desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=${label}
Comment=${label} (web app)
Exec=${CHROME_BIN} ${CHROME_FLAGS} --app=${url}
Terminal=false
Categories=Network;
StartupNotify=true
EOF
    echo "    [+] ${name}.desktop"
}

echo "--> Creating system-wide Chrome web app launchers…"

write_webapp "Zoom"                 "https://app.zoom.us/wc/home"              "Zoom"
write_webapp "Netflix"              "https://www.netflix.com"                "Netflix"
write_webapp "Spotify"              "https://open.spotify.com"               "Spotify"
write_webapp "Gmail"                "https://mail.google.com"                "Gmail"
write_webapp "Gemini"               "https://gemini.google.com"              "Gemini"
write_webapp "YouTube"              "https://www.youtube.com"                "YouTube"
write_webapp "PrimeVideo"           "https://www.primevideo.com"             "Prime Video"
write_webapp "DisneyPlus"           "https://www.disneyplus.com"             "Disney+"
write_webapp "HBOMax"               "https://play.max.com"                   "Max"
write_webapp "ChromeRemoteDesktop"  "https://remotedesktop.google.com/access" "Chrome Remote Desktop"
write_webapp "GoogleDocs"           "https://docs.google.com"                "Google Docs"
write_webapp "GoogleSheets"         "https://sheets.google.com"              "Google Sheets"
write_webapp "GoogleSlides"         "https://slides.google.com"              "Google Slides"
write_webapp "GoogleDrive"          "https://drive.google.com"               "Google Drive"

update-desktop-database "$APP_DST" 2>/dev/null || true

mark_done
echo "[${MODULE_ID}] Done."
