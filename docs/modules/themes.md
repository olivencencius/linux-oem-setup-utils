# `modules/themes.sh`

## Purpose

Deploys **Plank**, the **Malta** OEM wallpaper, the per-user **`oem-first-run.sh`**
helper, and the **`skel/`** autostart entries. **Does not** install theme or icon
packages or override GTK / icon / xfwm themes — distro defaults apply (Linux Mint
XFCE and Xubuntu).

On first login, `oem-first-run.sh` applies the wallpaper, moves XFCE **panel-1**
to the **top**, trims redundant panel plugins, and seeds the bottom **Plank** dock
(including a **Thunar** pin and the first available **software centre** `.desktop`
for the OS).

## Function exported

`step_themes`

## Inputs

- `$REPO_DIR/assets/wallpapers/malta.jpg`
- `$REPO_DIR/assets/scripts/oem-first-run.sh`
- `$REPO_DIR/skel/.` (typically `autostart` only)
- `ensure_apt_fresh` (for `apt-get install plank`)
- `$SUDO_USER` — when set, mirrors skel autostart and runs `oem-first-run.sh` for the live OEM session

## Outputs

- **apt:** `plank`
- **`/usr/share/backgrounds/oem-setup/malta.jpg`**
- **`/usr/local/bin/oem-first-run.sh`** (mode `755`)
- **`/etc/skel/...`** — copy of repo `skel/`
- **Live session:** copies `oem-first-run.desktop` and `touchegg-client.desktop`
  from skel into `$SUDO_HOME/.config/autostart`, then runs `oem-first-run.sh`

## Walkthrough

1. `ensure_apt_fresh` then `apt-get install -y plank`.
2. Copy wallpaper into `/usr/share/backgrounds/oem-setup/`.
3. Install `oem-first-run.sh` to `/usr/local/bin/`.
4. `cp -r "$REPO_DIR/skel/." /etc/skel/`
5. If `$SUDO_USER` is set: mirror autostart files, `chown`, run `oem-first-run.sh`.

## Uninstall counterpart

`step_uninstall` purges **`plank`**, removes **`/usr/share/backgrounds/oem-setup`**
and **`oem-first-run.sh`**, cleans **`/etc/skel`** and per-user Plank / marker files.
See [`uninstall.md`](../uninstall.md).
