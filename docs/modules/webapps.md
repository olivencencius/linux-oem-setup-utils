# `modules/webapps.sh`

## Purpose

Creates 11 Chrome `--app=` launchers and bundles their SVG icons so the
final desktop has "real" looking shortcuts for streaming, productivity,
and Google services without depending on remote icon URLs.

## Function exported

`step_web_apps`

## Inputs

- `$REPO_DIR/assets/icons/*.svg` (11 SVG files).
- `$REPO_DIR` (exported by `setup.sh`).

## Outputs

For each of the 11 web apps, two files are placed on the system:

- `/usr/share/applications/<Name>.desktop`
- `/usr/share/icons/hicolor/scalable/apps/<icon>.svg`

Plus a refreshed GTK icon cache (`gtk-update-icon-cache`) and a
refreshed desktop database (`update-desktop-database`).

## The 11 web apps

| `.desktop` filename | URL | Icon (basename) | Display name |
|---|---|---|---|
| `Netflix.desktop` | `https://www.netflix.com` | `netflix` | Netflix |
| `PrimeVideo.desktop` | `https://www.primevideo.com` | `primevideo` | Prime Video |
| `DisneyPlus.desktop` | `https://www.disneyplus.com` | `disneyplus` | Disney+ |
| `HBOMax.desktop` | `https://play.max.com` | `hbomax` | Max |
| `Spotify.desktop` | `https://open.spotify.com` | `spotify` | Spotify |
| `YouTube.desktop` | `https://www.youtube.com` | `youtube` | YouTube |
| `Gmail.desktop` | `https://mail.google.com` | `gmail` | Gmail |
| `GoogleDocs.desktop` | `https://docs.google.com` | `googledocs` | Google Docs |
| `GoogleDrive.desktop` | `https://drive.google.com` | `googledrive` | Google Drive |
| `Gemini.desktop` | `https://gemini.google.com` | `gemini` | Gemini |
| `ChromeRemoteDesktop.desktop` | `https://remotedesktop.google.com/access` | `chromeremotedesktop` | Chrome Remote Desktop |

## Walkthrough

### 1. Copy every icon

```bash
local ICON_SRC="$REPO_DIR/assets/icons"
local ICON_DST="/usr/share/icons/hicolor/scalable/apps"

mkdir -p "$ICON_DST"

cp "$ICON_SRC/netflix.svg"             "$ICON_DST/netflix.svg"
cp "$ICON_SRC/googledocs.svg"          "$ICON_DST/googledocs.svg"
…
cp "$ICON_SRC/chromeremotedesktop.svg" "$ICON_DST/chromeremotedesktop.svg"

gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
```

The icon-cache refresh's `|| true` is defensive: some Mint installs
have already-up-to-date caches and `gtk-update-icon-cache` returns
non-zero. We don't care.

### 2. Write each `.desktop` via the `write_webapp` helper

The module defines a single shared flag string used by every
launcher:

```bash
WEBAPP_CHROME_FLAGS='--password-store=basic --enable-features=OverlayScrollbar'
```

```bash
write_webapp() {
    local NAME="$1"     # .desktop basename (no extension)
    local URL="$2"      # URL Chrome opens with --app=
    local ICON="$3"     # icon basename
    local LABEL="$4"    # display Name= field

    cat > "$APP_DST/${NAME}.desktop" << EOF
[Desktop Entry]
Version=1.0
Name=${LABEL}
Exec=google-chrome ${WEBAPP_CHROME_FLAGS} --app="${URL}"
Terminal=false
Type=Application
Icon=${ICON}
Categories=Network;
StartupNotify=true
EOF
}
```

Then eleven `write_webapp` calls. Each `.desktop` looks like, for
Netflix:

```ini
[Desktop Entry]
Version=1.0
Name=Netflix
Exec=google-chrome --password-store=basic --enable-features=OverlayScrollbar --app="https://www.netflix.com"
Terminal=false
Type=Application
Icon=netflix
Categories=Network;
StartupNotify=true
```

The two extra flags fix concrete first-QA-run complaints:

| Flag | Symptom it fixes |
|---|---|
| `--password-store=basic` | Without it, Chrome auto-detects gnome-keyring on first launch and opens a "Choose password for new keyring" dialog before the web app's first paint. `basic` tells Chrome to store passwords as plaintext in the user's profile directory (web apps don't store credentials worth encrypting), bypassing the keyring entirely. |
| `--enable-features=OverlayScrollbar` | Switches the always-visible classic scrollbar (very prominent on a 720p / 1080p Chromebook screen) for the thin auto-hide overlay scrollbar that matches ChromeOS behaviour. |

### 3. Refresh the desktop database

```bash
update-desktop-database "$APP_DST" 2>/dev/null || true
```

Makes XFCE's whisker menu (and `oem-first-run.sh`, when it later
walks `/usr/share/applications/`) notice the new `.desktop` files
without requiring a re-login.

## Notes

- **`Categories=Network;` not `WebBrowser;`** — deliberate. The
  `WebBrowser` category would make XFCE consider these as candidates
  for the system's default browser, which is absurd ("default browser:
  Netflix").
- **Canonical `www.` hostnames** — `https://www.netflix.com`, not
  `https://netflix.com`. Chrome's `--app=` PWA mode only kicks in when
  the URL matches the canonical site. A redirect from `netflix.com`
  to `www.netflix.com` would briefly show a normal-Chrome window
  before redirecting, defeating the "looks like a native app"
  illusion.
- **`Icon=` is just the basename**, not a full path. The GTK theme
  search resolves `Icon=netflix` to `…/hicolor/scalable/apps/netflix.svg`
  via the icon cache.
- **Why bundle SVGs in the repo instead of fetching them?** Vendor
  icon URLs rot. A dependency on `https://some-favicon-cdn.example/
  netflix.svg` would mean a deployment from six months ago is now
  staring at a broken-image icon. Bundling the SVGs locks the visual
  result for a given commit.

## Idempotency

Fully idempotent — `cp` overwrites, the `cat > … << EOF` heredoc
overwrites, the cache refreshes are content-addressable. A re-run
results in byte-for-byte identical files.

## Uninstall counterpart

`step_uninstall` (sub-step 9):

- `rm` 11 `.desktop` files from `/usr/share/applications/`.
- `rm` 11 SVG icons from `/usr/share/icons/hicolor/scalable/apps/`.
- `gtk-update-icon-cache -f` to drop the icons from the cache.
- (The `update-desktop-database` refresh happens implicitly in
  sub-step 8b when the Powerwash desktop entry is removed.)
