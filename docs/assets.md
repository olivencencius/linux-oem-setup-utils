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
initial home.

The live `oem` account does **not** automatically pick up `/etc/skel`
because the OEM installer creates it *before* `setup.sh` runs.
`step_themes` therefore also explicitly mirrors the autostart entries
and `xsettings.xml` into `~oem/.config/` (chowned to the oem user) and
live-applies the theme and wallpaper to the running session via
`xfconf-query` / `xfsettingsd --replace`. It also runs
`oem-first-run.sh` inline so the bottom panel-2 dock appears
immediately during QA without needing a re-login.

### `skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml`

XFCE's `xsettings` channel persisted to disk. Sets the GTK theme to
`Mint-Y-Aqua` and the icon theme to `Papirus` for every new user.
`step_themes` also writes the same values via `xfconf-query` for the
live oem session and pushes the xfwm4 window-decoration theme to
`Mint-Y-Aqua` (xfconf channel `xfwm4`, property `/general/theme`).

### `skel/.config/autostart/*.desktop`

| File | Starts | Why per-user |
|---|---|---|
| `touchegg-client.desktop` | `touchegg --client` | The system `touchegg` daemon dispatches to per-user clients over D-Bus |
| `oem-first-run.desktop` | `bash -c "sleep 5 && /usr/local/bin/oem-first-run.sh"` | Self-deletes after first run; creates panel-2 dock on first login |

The 5-second sleep before `oem-first-run.sh` lets xfdesktop register its
monitors so the wallpaper applier can iterate over them and the panel
process is fully ready before the dock is created.

There is **no** `plank.desktop` or `imwheel.desktop` in the current
revision. Plank was replaced by a native XFCE panel-2 dock (created by
`oem-first-run.sh`). The `imwheel`-based scroll multiplier was removed
in favour of slowing libinput's native `ScrollPixelDistance` — see
[`modules/touchpad.md`](./modules/touchpad.md). `step_uninstall`
continues to clean legacy artefacts out of older installs.

### Bottom dock (panel-2) — created at first login, not staged in skel

There is no `skel/.config/xfce4/panel/launcher-NNN/` tree. The bottom
dock is not pre-staged in `/etc/skel`; it is created on demand by
`assets/scripts/oem-first-run.sh` (see
[`modules/themes.md`](./modules/themes.md)). The script runs
`xfconf-query` at first XFCE login to:

1. Append a `panel-2` to the existing `/panels` list (Mint's default
   `panel-1` is left untouched).
2. Set panel-2 properties (bottom-centered, length-adjust, 48 px size,
   semi-transparent background).
3. For each pinned app whose `.desktop` exists in
   `/usr/share/applications/`, allocate a plugin id ≥ 100, register it
   as a `launcher` plugin, and copy the `.desktop` into
   `~/.config/xfce4/panel/launcher-<pid>/`.
4. Run `xfce4-panel --restart` so the new panel appears immediately.

The pinned-app order, defined by the `DOCK_LAUNCHERS` array in the
script:

| Order | `.desktop` | Source |
|---|---|---|
| 1 | `google-chrome.desktop` | from `step_chrome` |
| 2 | `xfce4-settings-manager.desktop` | XFCE default |
| 3 | `thunar.desktop` | XFCE default |
| 4 | `vlc.desktop` | from `step_apps` |
| 5 | `Zoom.desktop` | from `step_zoom` |
| 6 | `Gmail.desktop` | from `step_web_apps` |
| 7 | `GoogleDocs.desktop` | from `step_web_apps` |
| 8 | `GoogleDrive.desktop` | from `step_web_apps` |
| 9 | `Gemini.desktop` | from `step_web_apps` |
| 10 | `YouTube.desktop` | from `step_web_apps` |
| 11 | `Spotify.desktop` | from `step_web_apps` |

If any `.desktop` is missing when `oem-first-run.sh` executes (e.g.
Zoom's download timed out), its launcher is silently skipped — which
is why [`pipeline.md`](./pipeline.md) is strict about
chrome/zoom/apps/webapps running before themes.

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
