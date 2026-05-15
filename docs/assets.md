# Assets and skel reference

Every static file under `assets/` and `skel/` is mapped here to its
runtime install path and the module that puts it there. If you're
chasing a "where does this thing on the live system come from?"
question, this is the index.

---

## `assets/configs/`

System-wide configuration files copied to their install path by a
module. None of these are sourced or executed — they are pure
configuration consumed by other services.

| Source (in repo) | Installed to | Placed by | Consumer |
|---|---|---|---|
| `assets/configs/touchegg.conf` | `/etc/touchegg/touchegg.conf` | `modules/gestures.sh` | `touchegg.service` |
| `assets/configs/oem-powerwash.desktop` | `/usr/share/applications/oem-powerwash.desktop` | `modules/powerwash.sh` | XFCE menu / `update-desktop-database` |
| `assets/configs/oem-powerwash.policy` | `/usr/share/polkit-1/actions/org.linuxoem.powerwash.policy` | `modules/powerwash.sh` | `polkitd` |
| `assets/configs/oem-powerwash-finalize.service` | `/etc/systemd/system/oem-powerwash-finalize.service` | `modules/powerwash.sh` | `systemd` |

Detail on the Powerwash quartet is in [`powerwash.md`](./powerwash.md).

---

## `assets/icons/`

Hicolor-scalable SVG icons. All copied by either `step_web_apps` or
`step_powerwash` into the standard scalable apps directory, after which
the GTK icon cache is refreshed.

| Source | Installed to | Placed by |
|---|---|---|
| `assets/icons/netflix.svg` | `/usr/share/icons/hicolor/scalable/apps/netflix.svg` | `modules/webapps.sh` |
| `assets/icons/primevideo.svg` | `…/primevideo.svg` | `modules/webapps.sh` |
| `assets/icons/disneyplus.svg` | `…/disneyplus.svg` | `modules/webapps.sh` |
| `assets/icons/hbomax.svg` | `…/hbomax.svg` | `modules/webapps.sh` |
| `assets/icons/youtube.svg` | `…/youtube.svg` | `modules/webapps.sh` |
| `assets/icons/spotify.svg` | `…/spotify.svg` | `modules/webapps.sh` |
| `assets/icons/gmail.svg` | `…/gmail.svg` | `modules/webapps.sh` |
| `assets/icons/googledocs.svg` | `…/googledocs.svg` | `modules/webapps.sh` |
| `assets/icons/googledrive.svg` | `…/googledrive.svg` | `modules/webapps.sh` |
| `assets/icons/gemini.svg` | `…/gemini.svg` | `modules/webapps.sh` |
| `assets/icons/chromeremotedesktop.svg` | `…/chromeremotedesktop.svg` | `modules/webapps.sh` |
| `assets/icons/oem-powerwash.svg` | `…/oem-powerwash.svg` | `modules/powerwash.sh` |

The `Icon=` field in each `.desktop` file references the **basename
without extension**, e.g. `Icon=netflix`. The theme search resolves that
to the file in the scalable apps directory.

---

## `assets/scripts/`

Helper shell scripts that *run on the deployed machine* (as opposed to
the modules in `modules/`, which run during deployment). Each one is
installed by exactly one module.

| Source | Installed to | Mode | Placed by | Runs as | When |
|---|---|---|---|---|---|
| `assets/scripts/oem-first-run.sh` | `/usr/local/bin/oem-first-run.sh` | `755` | `modules/themes.sh` | the buyer (per user) | first XFCE login, via skel autostart |
| `assets/scripts/oem-powerwash.sh` | `/usr/local/bin/oem-powerwash.sh` | `755` | `modules/powerwash.sh` | the buyer | when they launch *Powerwash* from the menu |
| `assets/scripts/oem-powerwash-arm.sh` | `/usr/local/sbin/oem-powerwash-arm.sh` | `700` | `modules/powerwash.sh` | root, via `pkexec` | after the buyer passes both confirmations + admin auth |
| `assets/scripts/oem-powerwash-finalize.sh` | `/usr/local/sbin/oem-powerwash-finalize.sh` | `700` | `modules/powerwash.sh` | root, via systemd | next boot after a confirmed Powerwash |

Two `sbin` scripts are mode `700` (root-only) on purpose: the polkit
flow already prevents an unprivileged user from invoking them directly,
and chmod 700 closes a defence-in-depth gap if someone were to find
another way in.

`oem-first-run.sh` and the Powerwash trio are documented in
[`modules/themes.md`](./modules/themes.md) and
[`powerwash.md`](./powerwash.md) respectively.

---

## `assets/wallpapers/`

| Source | Installed to | Placed by | Consumer |
|---|---|---|---|
| `assets/wallpapers/malta.jpg` | `/usr/share/backgrounds/oem-setup/malta.jpg` | `modules/themes.sh` | `oem-first-run.sh` (sets it per-user via xfconf) |

Why not `/usr/share/backgrounds/<distro>/`? Because that directory is
managed by the Mint backgrounds package and any package update can
overwrite or remove files dropped into it. The `oem-setup` subdirectory
is ours and is removed cleanly by `step_uninstall`.

---

## `skel/` — the user-default tree

`step_themes` does **one** `cp -r "$REPO_DIR/skel/." /etc/skel/`. After
that, every newly created user account inherits this tree as their
initial home. The live `oem` account doesn't, because the OEM
installer creates it *before* `setup.sh` runs — `step_themes` and
`step_touchpad` apply a few of these files to that user explicitly.

### `skel/.imwheelrc`

The single source of truth for the scroll-speed multiplier. `imwheel`
intercepts X11 scroll events and re-emits them N times — here N=3:

```
".*"
None, Up, Up, 3
None, Down, Down, 3
Control_L, Up, Control_L|Up
Control_L, Down, Control_L|Down
Shift_L, Up, Shift_L|Up
Shift_L, Down, Shift_L|Down
```

Why imwheel and not libinput? See [`modules/touchpad.md`](./modules/touchpad.md).

### `skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml`

XFCE's `xsettings` channel persisted to disk. Sets the GTK theme to
`ChromeOS` and the icon theme to `Tela-blue` for every new user. The
first-run script also sets these via `xfconf-query` to cover the live
oem session.

### `skel/.config/autostart/*.desktop`

| File | Starts | Why per-user |
|---|---|---|
| `plank.desktop` | `bash -c "sleep 3 && plank"` | One Plank per user; the 3s sleep waits for the panel to draw so Plank doesn't overlap the XFCE panel |
| `imwheel.desktop` | `imwheel` | imwheel is a per-user X11 client (no system service) |
| `touchegg-client.desktop` | `touchegg --client` | The system `touchegg` daemon dispatches to per-user clients over D-Bus |
| `oem-first-run.desktop` | `bash -c "sleep 5 && /usr/local/bin/oem-first-run.sh"` | Self-deletes after first run |

The 5-second sleep before `oem-first-run.sh` lets xfdesktop register its
monitors so the wallpaper applier can iterate over them.

### `skel/.config/plank/dock1/launchers/*.dockitem`

Eleven Plank dockitems, one per launcher. Each is a two-line INI file:

```
[PlankItemsDockItemPreferences]
Launcher=file:///usr/share/applications/google-chrome.desktop
```

Plank itself decides *which* of these are on the dock and in *what
order* from the system dconf override at
`/etc/dconf/db/local.d/00-plank` (written by `step_themes`). The
dockitems just have to exist; the dconf `dock-items=[…]` key is the
ordered list.

The eleven files:

| File | Points at |
|---|---|
| `google-chrome.dockitem` | `/usr/share/applications/google-chrome.desktop` |
| `xfce4-settings-manager.dockitem` | `/usr/share/applications/xfce4-settings-manager.desktop` |
| `thunar.dockitem` | `/usr/share/applications/thunar.desktop` |
| `vlc.dockitem` | `/usr/share/applications/vlc.desktop` |
| `zoom.dockitem` | `/usr/share/applications/Zoom.desktop` |
| `gmail.dockitem` | `/usr/share/applications/Gmail.desktop` |
| `googledocs.dockitem` | `/usr/share/applications/GoogleDocs.desktop` |
| `googledrive.dockitem` | `/usr/share/applications/GoogleDrive.desktop` |
| `gemini.dockitem` | `/usr/share/applications/Gemini.desktop` |
| `youtube.dockitem` | `/usr/share/applications/YouTube.desktop` |
| `spotify.dockitem` | `/usr/share/applications/Spotify.desktop` |

If any of those `.desktop` files is missing when Plank loads, the
dockitem is silently dropped from the dock. That is why
[`pipeline.md`](./pipeline.md) is strict about chrome/zoom/apps/webapps
running before themes.

---

## What `/var/lib/oem-setup/` looks like on a deployed machine

Not part of the repo, but the runtime sibling of this assets map:

```
/var/lib/oem-setup/
├── state/                        ← per-step .done markers, kb_layout
└── backups/                      ← snapshots of system files before mutation
    ├── grub                      ← /etc/default/grub (from hardware.sh)
    ├── modules                   ← /etc/initramfs-tools/modules (hardware.sh)
    ├── inputrc                   ← /etc/inputrc (terminal.sh)
    ├── keyboard                  ← /etc/default/keyboard (regional.sh)
    └── user                      ← /etc/dconf/profile/user (themes.sh)
```

And, only after a buyer has *armed* a powerwash:

```
/var/lib/oem-setup/powerwash.flag  ← consumed and deleted by oem-powerwash-finalize.sh
```

The flag file is the entire interface between the user-space arm step
and the boot-time finalize service. See [`powerwash.md`](./powerwash.md).
