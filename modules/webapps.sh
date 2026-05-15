#!/bin/bash
# ==============================================================================
#   Module:    webapps.sh
#   Purpose:   Create 11 Chrome `--app=` launchers (Netflix, Prime Video,
#              Disney+, Max, Spotify, YouTube, Gmail, Docs, Drive, Gemini,
#              Chrome Remote Desktop) and bundle their SVG icons.
#   Reads:     REPO_DIR/assets/icons/*.svg
#   Writes:    /usr/share/applications/{Netflix,PrimeVideo,DisneyPlus,HBOMax,
#                                       Spotify,YouTube,Gmail,GoogleDocs,
#                                       GoogleDrive,Gemini,
#                                       ChromeRemoteDesktop}.desktop
#              /usr/share/icons/hicolor/scalable/apps/{netflix,primevideo,
#                                       disneyplus,hbomax,spotify,youtube,
#                                       gmail,googledocs,googledrive,gemini,
#                                       chromeremotedesktop}.svg
#   Refreshes: gtk-update-icon-cache /usr/share/icons/hicolor
#              update-desktop-database /usr/share/applications
#   Step fn:   step_web_apps
#   Docs:      docs/modules/webapps.md
#   Uninstall: step_uninstall removes all 11 .desktop entries and all 11
#              icons (sub-step 9), refreshes the icon cache.
#
#   NOTE: Categories=Network; (NOT WebBrowser;) is deliberate — these
#   shortcuts must not appear as system "default browser" candidates.
# ==============================================================================

step_web_apps() {
    echo "--> Installing branded web-app shortcuts..."

    local ICON_SRC="$REPO_DIR/assets/icons"
    local ICON_DST="/usr/share/icons/hicolor/scalable/apps"
    local APP_DST="/usr/share/applications"

    mkdir -p "$ICON_DST"

    # Copy all bundled icons into the hicolor theme directory
    cp "$ICON_SRC/netflix.svg"              "$ICON_DST/netflix.svg"
    cp "$ICON_SRC/googledocs.svg"           "$ICON_DST/googledocs.svg"
    cp "$ICON_SRC/googledrive.svg"          "$ICON_DST/googledrive.svg"
    cp "$ICON_SRC/gmail.svg"                "$ICON_DST/gmail.svg"
    cp "$ICON_SRC/spotify.svg"              "$ICON_DST/spotify.svg"
    cp "$ICON_SRC/gemini.svg"               "$ICON_DST/gemini.svg"
    cp "$ICON_SRC/primevideo.svg"           "$ICON_DST/primevideo.svg"
    cp "$ICON_SRC/disneyplus.svg"           "$ICON_DST/disneyplus.svg"
    cp "$ICON_SRC/hbomax.svg"               "$ICON_DST/hbomax.svg"
    cp "$ICON_SRC/youtube.svg"              "$ICON_DST/youtube.svg"
    cp "$ICON_SRC/chromeremotedesktop.svg"  "$ICON_DST/chromeremotedesktop.svg"

    gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true

    # -------------------------------------------------------------------------
    # Helper — write a .desktop file for a Chrome web app
    # Usage: write_webapp NAME URL ICON_NAME DISPLAY_NAME
    # -------------------------------------------------------------------------
    write_webapp() {
        local NAME="$1"
        local URL="$2"
        local ICON="$3"
        local LABEL="$4"

        cat > "$APP_DST/${NAME}.desktop" << EOF
[Desktop Entry]
Version=1.0
Name=${LABEL}
Exec=google-chrome --app="${URL}"
Terminal=false
Type=Application
Icon=${ICON}
Categories=Network;
StartupNotify=true
EOF
    }

    # Streaming — canonical www. hostnames so Chrome enters PWA mode reliably
    write_webapp "Netflix"              "https://www.netflix.com"                   "netflix"             "Netflix"
    write_webapp "PrimeVideo"           "https://www.primevideo.com"                "primevideo"          "Prime Video"
    write_webapp "DisneyPlus"           "https://www.disneyplus.com"                "disneyplus"          "Disney+"
    write_webapp "HBOMax"               "https://play.max.com"                      "hbomax"              "Max"
    write_webapp "Spotify"              "https://open.spotify.com"                  "spotify"             "Spotify"
    write_webapp "YouTube"              "https://www.youtube.com"                   "youtube"             "YouTube"

    # Productivity & communication
    write_webapp "Gmail"                "https://mail.google.com"                   "gmail"               "Gmail"
    write_webapp "GoogleDocs"           "https://docs.google.com"                   "googledocs"          "Google Docs"
    write_webapp "GoogleDrive"          "https://drive.google.com"                  "googledrive"         "Google Drive"
    write_webapp "Gemini"               "https://gemini.google.com"                 "gemini"              "Gemini"
    write_webapp "ChromeRemoteDesktop"  "https://remotedesktop.google.com/access"   "chromeremotedesktop" "Chrome Remote Desktop"

    update-desktop-database "$APP_DST" 2>/dev/null || true

    echo "    [+] Web app shortcuts created."
}
