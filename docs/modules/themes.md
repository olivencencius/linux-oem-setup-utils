# `modules/themes.sh`

## Purpose

The biggest module by far. Wires together five concerns that together
make the desktop look like ChromeOS:

1. The **ChromeOS GTK theme** (window decorations, controls,
   selection colours).
2. The **Tela-blue icon theme** (the blue circular-shaped app icons).
3. The **Plank dock** at the bottom of the screen with 11 pinned
   apps in a fixed order.
4. The **Malta wallpaper**.
5. The **per-user first-run script** that applies theme + wallpaper
   to every detected monitor on first login.

It also stages the entire `skel/` tree into `/etc/skel` so every new
user inherits the right defaults.

## Function exported

`step_themes`

(Plus the internal helper `oem_user_xrun`.)

## Inputs

- Live network (clones two GitHub repos).
- `$REPO_DIR` (for `assets/wallpapers/malta.jpg`,
  `assets/scripts/oem-first-run.sh`, and the entire `skel/` tree).
- `$SUDO_USER` (optional) — if set, the live oem session has the
  theme applied immediately for QA.
- `ensure_apt_fresh` and `backup_once` (helpers from `setup.sh`).

## Outputs

Installed packages:

- `plank` from apt.

System-wide files placed:

- `/usr/share/themes/ChromeOS*` and `/usr/share/themes/ChromeOS-dark*`
  etc. — from the upstream installer.
- `/usr/share/icons/Tela-blue*` and `/usr/share/icons/Tela-blue-dark*`
  — from the upstream installer (only the `blue` variant).
- `/etc/dconf/profile/user` — appended `user-db:user` and
  `system-db:local` lines (idempotently).
- `/etc/dconf/db/local.d/00-plank` — written verbatim with the
  ordered `dock-items=[…]` key, plus theme, position, icon-size,
  hide-mode.
- `/etc/dconf/db/local` — generated/refreshed by `dconf update`.
- `/usr/share/backgrounds/oem-setup/malta.jpg` — the wallpaper file.
- `/usr/local/bin/oem-first-run.sh` — the per-user theme/wallpaper
  applier (mode `755`).
- The entire `/etc/skel/` tree from `$REPO_DIR/skel/.` (`cp -r`).

Backups taken (via `backup_once`):

- `/etc/dconf/profile/user` (if it existed before this step ran).

Live session changes (only when `$SUDO_USER` is set):

- `xfconf-query -c xsettings -p /Net/ThemeName -s ChromeOS`.
- `xfconf-query -c xsettings -p /Net/IconThemeName -s Tela-blue`.

## Walkthrough

### 1. The themes themselves

```bash
cd /tmp
rm -rf ChromeOS-theme Tela-icon-theme

git clone --depth 1 https://github.com/vinceliuice/ChromeOS-theme.git
./ChromeOS-theme/install.sh                   # ChromeOS GTK theme

git clone --depth 1 https://github.com/vinceliuice/Tela-icon-theme.git
./Tela-icon-theme/install.sh blue             # ONLY the blue variant

rm -rf /tmp/ChromeOS-theme /tmp/Tela-icon-theme
```

`install.sh blue` is the key call. Without the explicit variant,
Tela's installer drops every colour variant (~100 MB) under
`/usr/share/icons/Tela-*`. On 4 GB eMMC machines that's a meaningful
amount of disk for variants the toolkit never references.

### 2. Plank from apt

```bash
ensure_apt_fresh
apt-get install -y plank
```

We use the apt-packaged Plank rather than building it. Mint's repo
carries a recent-enough version, and an apt package is straightforward
to purge cleanly in `step_uninstall`.

The comment in the module documents that the system-wide autostart
file `/etc/xdg/autostart/plank.desktop` is **not** dropped here. The
per-user skel autostart entry (`skel/.config/autostart/plank.desktop`)
is the single source of truth. A duplicate entry caused harmless but
ugly D-Bus warnings on login.

### 3. The dconf system database

```bash
mkdir -p /etc/dconf/profile
backup_once /etc/dconf/profile/user

if [ -f /etc/dconf/profile/user ]; then
    grep -qxF 'user-db:user'    /etc/dconf/profile/user || echo 'user-db:user'    >> /etc/dconf/profile/user
    grep -qxF 'system-db:local' /etc/dconf/profile/user || echo 'system-db:local' >> /etc/dconf/profile/user
else
    printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
fi

mkdir -p /etc/dconf/db/local.d
cat > /etc/dconf/db/local.d/00-plank << 'EOF'
[net/launchpad/plank/docks/dock1]
theme='Transparent'
position='bottom'
icon-size=48
hide-mode='none'
dock-items=['google-chrome.dockitem', 'xfce4-settings-manager.dockitem', 'thunar.dockitem', 'vlc.dockitem', 'zoom.dockitem', 'gmail.dockitem', 'googledocs.dockitem', 'googledrive.dockitem', 'gemini.dockitem', 'youtube.dockitem', 'spotify.dockitem']
EOF
dconf update
```

Three things going on:

1. **dconf profile**: a two-line file that tells dconf "compose the
   effective settings from the user DB *plus* a system DB called
   `local`". Without both lines, Plank ignores the system override.
2. **System override file** at `/etc/dconf/db/local.d/00-plank` —
   the `00-` prefix is conventional, but irrelevant in practice since
   there are no other override files.
3. **`dconf update`** compiles `/etc/dconf/db/local.d/` into a binary
   blob at `/etc/dconf/db/local` that dconf consults on each query.
   Without this call, the override file is ignored.

The `dock-items=` value is the *ordered list* Plank uses to decide
which `.dockitem` files to show and in what order. Anything not in
this list is silently ignored even if the `.dockitem` exists.

### 4. Wallpaper deploy

```bash
mkdir -p /usr/share/backgrounds/oem-setup
cp "$REPO_DIR/assets/wallpapers/malta.jpg" /usr/share/backgrounds/oem-setup/malta.jpg
```

Wallpaper goes into our own subdirectory so a Mint backgrounds package
update can't blow it away.

### 5. First-run applier

```bash
install -m 755 "$REPO_DIR/assets/scripts/oem-first-run.sh" /usr/local/bin/oem-first-run.sh
```

This is the script that runs *per user on first login* and applies
the wallpaper to every detected monitor. See
[`../powerwash.md`](../powerwash.md) for nothing — wrong file. See
`assets/scripts/oem-first-run.sh` itself, documented below.

`/usr/local/bin/` is the conventional location for system-administrator
scripts; mode `755` because it must be executable by any user.

### 6. Stage skel

```bash
cp -r "$REPO_DIR/skel/." /etc/skel/
```

One copy of the entire tree:

- `/etc/skel/.imwheelrc`
- `/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml`
- `/etc/skel/.config/autostart/plank.desktop`
- `/etc/skel/.config/autostart/imwheel.desktop`
- `/etc/skel/.config/autostart/touchegg-client.desktop`
- `/etc/skel/.config/autostart/oem-first-run.desktop`
- `/etc/skel/.config/plank/dock1/launchers/*.dockitem` (11 files)

See [`../assets.md`](../assets.md) for the full per-file table.

### 7. Live-session apply (QA visibility)

```bash
if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null; then
    oem_user_xrun "$SUDO_USER" xfconf-query -c xsettings -p /Net/ThemeName     -s "ChromeOS"  || true
    oem_user_xrun "$SUDO_USER" xfconf-query -c xsettings -p /Net/IconThemeName -s "Tela-blue" || true
fi
```

The `oem_user_xrun` helper is the most subtle piece in this module.
See the next section.

## The `oem_user_xrun` helper

```bash
oem_user_xrun() {
    local user="$1"; shift
    local home dbus_addr
    home=$(getent passwd "$user" | cut -d: -f6)

    local pid
    pid=$(pgrep -u "$user" -x xfsettingsd 2>/dev/null | head -1 || true)
    [ -z "$pid" ] && pid=$(pgrep -u "$user" -x xfce4-session 2>/dev/null | head -1 || true)

    if [ -n "$pid" ] && [ -r "/proc/$pid/environ" ]; then
        dbus_addr=$(tr '\0' '\n' < "/proc/$pid/environ" \
                    | awk '/^DBUS_SESSION_BUS_ADDRESS=/{ print substr($0, index($0,"=")+1); exit }' || true)
    fi

    sudo -u "$user" \
        DISPLAY="${DISPLAY:-:0}" \
        XAUTHORITY="$home/.Xauthority" \
        DBUS_SESSION_BUS_ADDRESS="${dbus_addr:-}" \
        "$@"
}
```

To make `xfconf-query` actually persist a value in the live oem
session, three environment variables must be set correctly *for the
caller*:

- `DISPLAY` — which X display to talk to (`:0` in 99% of cases).
- `XAUTHORITY` — the user's Xauth cookie file (`$HOME/.Xauthority`).
- `DBUS_SESSION_BUS_ADDRESS` — the per-user D-Bus session bus that
  `xfconfd` is listening on.

The first two are easy. The third is the problem: it's not
predictable. Mint's xfconfd talks to a session bus whose socket path
is generated at session start (typically `unix:path=/tmp/dbus-XXXX`
or `unix:abstract=...`). We have to *discover* it.

The trick is to look at the environment of a process that's already
running in the user's session — `xfsettingsd` is reliably present in
XFCE, with `xfce4-session` as a fallback. `/proc/<pid>/environ` is the
NUL-separated environment of that process, readable by the same user
(and by root). The `tr '\0' '\n' | awk` pipeline extracts the
`DBUS_SESSION_BUS_ADDRESS=` line.

Important detail: the value itself can contain `=` (e.g.
`unix:path=/tmp/dbus-XXXX`). A naive `cut -d= -f2` would truncate it.
The `awk` uses `index($0, "=")` to find only the *first* `=` and
returns everything after it.

If the discovery fails (no XFCE session running, no readable
`environ`), `dbus_addr` is empty and `xfconf-query` writes silently
nowhere — but that's fine, because the skel xsettings.xml is the
final fallback and will apply on next login.

## Notes

- The dock theme is set to `'Transparent'`. Plank ships this theme
  by default; no extra install needed.
- `position='bottom'` and `icon-size=48` together produce a dock that
  visually matches ChromeOS's shelf height.
- `hide-mode='none'` keeps the dock always visible. ChromeOS hides
  its shelf in tablet mode; we don't have an equivalent on Linux, so
  always-visible is the better default.
- The autoclean of `/tmp/ChromeOS-theme` / `/tmp/Tela-icon-theme` at
  the end of the themes block is **in addition to** the same paths
  in `step_cleanup`. Defensive — the upstream installers may leave
  build artefacts that `cleanup` would normally clear next run.

## Idempotency

Fully idempotent for everything *except* the upstream `install.sh`
scripts, which are themselves idempotent (overwrite their target
files). A re-run:

- Re-clones the theme repos (fast, shallow).
- Re-installs the themes (overwrites identical files).
- Re-runs `apt-get install -y plank` (no-op if already installed).
- `grep -qxF` guards prevent appending duplicate lines to
  `/etc/dconf/profile/user`.
- The dconf override is `cat > … << EOF` which truncates and rewrites
  — byte-for-byte stable.
- `cp -r "$REPO_DIR/skel/." /etc/skel/` is idempotent for the same
  files; if a previous run modified `/etc/skel/` with extra files, a
  re-run does **not** remove them (cp doesn't delete). `step_uninstall`
  is the one with the explicit "remove our skel artefacts" logic.

## Uninstall counterpart

`step_uninstall` (sub-steps 4, 8, 12):

- **Themes (4)**: re-clone upstream and run `install.sh -r` (their
  uninstaller). Notes added to `UNINSTALL_NOTES` if the clone or `-r`
  flag fails.
- **Plank package (2)**: `apt purge plank`.
- **dconf override (8)**: `rm /etc/dconf/db/local.d/00-plank`,
  `dconf update`.
- **dconf profile (8)**: `restore_or_skip /etc/dconf/profile/user`
  or sed-remove our two lines; remove the file if empty.
- **Wallpaper (8)**: `rm -rf /usr/share/backgrounds/oem-setup`.
- **First-run script (8)**: `rm /usr/local/bin/oem-first-run.sh`.
- **`/etc/skel` cleanup (12)**: explicit `rm` of every file this
  module placed there, plus the per-user mirror under `~/`.
