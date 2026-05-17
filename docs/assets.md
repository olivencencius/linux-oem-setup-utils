# Assets and skel reference

Every static file under `assets/` and `skel/` is mapped here to its
runtime install path and the module that puts it there.

---

## `assets/configs/`

| Source (in repo) | Installed to | Placed by | Consumer |
|---|---|---|---|
| `assets/configs/touchegg.conf` | `/etc/touchegg/touchegg.conf` | `modules/gestures.sh` | `touchegg.service` |
| `assets/configs/oem-workspace-overview.desktop` | `/usr/share/applications/oem-workspace-overview.desktop` | `modules/gestures.sh` | Plank / menu — `xfdashboard` |

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

See [`modules/themes.md`](./modules/themes.md) for behaviour (wallpaper, top panel, Plank dock).

---

## `assets/wallpapers/`

| Source | Installed to | Placed by | Consumer |
|---|---|---|---|
| `assets/wallpapers/malta.jpg` | `/usr/share/backgrounds/oem-setup/malta.jpg` | `modules/themes.sh` | `oem-first-run.sh` |

The `oem-setup` subdirectory is owned by this toolkit and removed by `step_uninstall`.

---

## `skel/` — user-default tree

`step_themes` runs `cp -r "$REPO_DIR/skel/." /etc/skel/`. New user accounts inherit these files.

The live `oem` account does **not** automatically pick up `/etc/skel`
(because it pre-exists). `step_themes` mirrors **`autostart`** into
`~oem/.config/autostart/` and runs `oem-first-run.sh` inline.

### `skel/.config/autostart/*.desktop`

| File | Starts | Why |
|---|---|---|
| `touchegg-client.desktop` | `touchegg --client` | Per-user client for the system `touchegg` daemon |
| `oem-first-run.desktop` | `bash -c "sleep 5 && /usr/local/bin/oem-first-run.sh"` | One-shot: wallpaper, panel layout, Plank; removes its own autostart when done |

The sleep lets `xfdesktop` register monitors before the wallpaper loop runs.

**Plank** is started from `~/.config/autostart/plank.desktop`, written by
`oem-first-run.sh` (not staged in skel).

Pinned launcher order is the `DOCK_LAUNCHERS` logic in `oem-first-run.sh`
(including resolved Thunar + software-centre `.desktop` names).

---

## `/var/lib/oem-setup/` on a deployed machine

```
/var/lib/oem-setup/
├── state/                        ← per-step .done markers, kb_layout
└── backups/                      ← snapshots before mutation
    ├── grub
    ├── modules
    ├── inputrc
    └── keyboard
```
