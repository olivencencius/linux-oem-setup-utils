# Assets and skel reference

Every static file under `assets/` and `skel/` is mapped here to its
runtime install path and the module that puts it there.

---

## `assets/configs/`

| Source (in repo) | Installed to | Placed by | Consumer |
|---|---|---|---|
| `assets/configs/libinput-gestures.conf` | `/etc/libinput-gestures.conf` | `modules/gestures.sh` | **`libinput-gestures`** (per-session daemon) |
| `assets/configs/oem-workspace-overview.desktop` | `/usr/share/applications/oem-workspace-overview.desktop` | `modules/gestures.sh` | Plank / menu — `xfdashboard` |
| `assets/configs/oem-prepare-shipping.desktop` | *(not installed by the toolkit)* | — | Optional: copy manually if you install `oem-prepare-shipping.sh` to `/usr/local/bin` and want **`pkexec`** — **`Exec=`** targets that path |

---

## `assets/icons/`

Hicolor-scalable SVG icons. Copied by `step_web_apps`, then the GTK icon cache is refreshed.

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
| `assets/icons/googlesheets.svg` | `…/googlesheets.svg` | `modules/webapps.sh` |
| `assets/icons/googleslides.svg` | `…/googleslides.svg` | `modules/webapps.sh` |
| `assets/icons/googledrive.svg` | `…/googledrive.svg` | `modules/webapps.sh` |
| `assets/icons/gemini.svg` | `…/gemini.svg` | `modules/webapps.sh` |
| `assets/icons/chromeremotedesktop.svg` | `…/chromeremotedesktop.svg` | `modules/webapps.sh` |

The `Icon=` field in each `.desktop` file references the **basename
without extension**, e.g. `Icon=netflix`.

---

## `assets/scripts/`

| Source | Installed to | Mode | Placed by | Runs as | When |
|---|---|---|---|---|---|
| `assets/scripts/oem-first-run.sh` | `/usr/local/bin/oem-first-run.sh` | `755` | `modules/themes.sh` | each user | first XFCE login (skel autostart) or inline during `step_themes` |
| `assets/scripts/oem-add-workspace.sh` | `/usr/local/bin/oem-add-workspace.sh` | `755` | `modules/gestures.sh` | each user | **Super+Insert** (xfce4-keyboard-shortcuts), seeded by **`oem-first-run.sh`** |
| `assets/scripts/oem-sync-all-user-homes.sh` | *(not installed)* | `755` | — | root | Ad-hoc: preflight (wallpaper, web apps, games, dock `.desktop`) then sync autostart + inputrc + `input` for uid 1000–65533; **`--reset`**, **`--strict`**, **`--dry-run`** |
| `assets/scripts/oem-prepare-shipping.sh` | *(not installed by the toolkit)* | `755` | — | root | Run standalone (`sudo bash …` or wget \| sudo bash) — installs **`oem-config`** if needed, then **`oem-config-prepare`** |

See [`modules/themes.md`](./modules/themes.md) for behaviour (wallpaper, top panel, Plank dock).

---

## `assets/wallpapers/`

| Source | Installed to | Placed by | Consumer |
|---|---|---|---|
| `assets/wallpapers/malta.jpg` | `/usr/share/backgrounds/oem-setup/malta.jpg` | `modules/themes.sh` | `oem-first-run.sh` |

The `oem-setup` subdirectory is owned by this toolkit and removed by `step_uninstall`.

---

## `skel/` — user-default tree

`step_themes` runs `cp -r "$REPO_DIR/skel/." /etc/skel/` (no pipeline-generated
**`Desktop/`** handover launcher).

The live technician account does **not** automatically pick up `/etc/skel`
(because it pre-exists). **`step_themes`** syncs **oem-first-run** autostart to
every UID **1000–65533** home without **`.oem-first-run-done`**, and runs
**`oem-first-run.sh`** inline for **`$SUDO_USER`** when possible.

### `skel/.config/autostart/*.desktop`

| File | Starts | Why |
|---|---|---|
| `oem-first-run.desktop` | `bash -c "sleep 5 && /usr/local/bin/oem-first-run.sh"` | One-shot: wallpaper, panel layout, Plank; removes its own autostart when done |

**Legacy note:** `touchegg-client.desktop` was removed from the repo as part of the migration from **Touchegg** to **libinput-gestures**. References in **`step_uninstall`** remain for defensive cleanup of legacy OEM deployments.

The sleep lets `xfdesktop` register monitors before the wallpaper loop runs.

**Touchpad gestures** use **`libinput-gestures`**, autostarted from **`/etc/xdg/autostart/libinput-gestures.desktop`** system-wide — not mirrored under **`/etc/skel`**.

**Plank** is started from `~/.config/autostart/plank.desktop`, written by
`oem-first-run.sh` (not staged in skel).

Pinned launcher order is the `DOCK_LAUNCHERS` logic in `oem-first-run.sh`
(including resolved Thunar + software-centre `.desktop` names).

**Handover:** `assets/scripts/oem-prepare-shipping.sh` and
`assets/configs/oem-prepare-shipping.desktop` stay in the repo only; operators
run the script when needed (see README / handover QA).

## `/var/lib/oem-setup/` on a deployed machine

```
/var/lib/oem-setup/
├── state/                        ← per-step `.done` markers only
└── backups/                      ← snapshots before mutation
    ├── grub
    ├── modules
    ├── inputrc
    ├── keyboard
    └── adduser.conf
```
