# `modules/themes.sh`

## Purpose

Deploys **Plank**, the **Malta** OEM wallpaper, the per-user **`oem-first-run.sh`**
helper, Ubuntu **OEM handover launcher** assets (desktop launcher,
`/usr/local/bin/oem-prepare-shipping` — packages **`oem-config`** /
**`oem-config-gtk`** are installed later by **`step_oem_handover`**), and the
**`skel/`** autostart entries.
**Does not** install theme or icon packages or override GTK / icon / xfwm themes
— distro defaults apply (**Xubuntu**).

On first login, `oem-first-run.sh` applies the wallpaper, moves XFCE **panel-1**
to the **top**, trims redundant panel plugins, ensures a **workspace pager**,
seeds **xfwm4** workspace defaults (minimum four desks, friendly names when there
are exactly four), binds **Super+Tab** to **rofi** window mode (when `rofi` is
installed by `step_gestures_and_workspaces`), **Super+Insert** to add a desk, and seeds the bottom **Plank** dock
(including a **Thunar** pin and the first available **software centre** `.desktop`
for the OS).

## Function exported

`step_themes`

## Inputs

- `$REPO_DIR/assets/wallpapers/malta.jpg`
- `$REPO_DIR/assets/scripts/oem-first-run.sh`
- `$REPO_DIR/assets/scripts/oem-prepare-shipping.sh`
- `$REPO_DIR/assets/configs/oem-prepare-shipping.desktop`
- `$REPO_DIR/skel/.` (typically `autostart`; `Desktop/` is added by this step)
- `ensure_apt_fresh` (for apt installs)
- `$SUDO_USER` — when set, mirrors skel **autostart** and **Desktop** into the
  live session and runs `oem-first-run.sh` inline

## Outputs

- **apt:** `plank` (`oem-config` / `oem-config-gtk`: see **`modules/oem_handover.sh`**)
- **`/usr/share/backgrounds/oem-setup/malta.jpg`**
- **`/usr/local/bin/oem-first-run.sh`** (mode `755`)
- **`/usr/local/bin/oem-prepare-shipping`** (mode `755`)
- **`/usr/share/applications/oem-prepare-shipping.desktop`**
- **`/etc/skel/...`** — copy of repo `skel/` plus **`Desktop/oem-prepare-shipping.desktop`**
- **Live session:** copies autostart `.desktop` files and the handover launcher
  into `$SUDO_HOME`, then runs `oem-first-run.sh`

## Walkthrough

1. `ensure_apt_fresh` then `apt-get install -y plank`.
2. Install `oem-prepare-shipping.sh` and `oem-prepare-shipping.desktop` system-wide.
3. Copy wallpaper into `/usr/share/backgrounds/oem-setup/`.
4. Install `oem-first-run.sh` to `/usr/local/bin/`.
5. `cp -r "$REPO_DIR/skel/." /etc/skel/`; create `/etc/skel/Desktop/` and copy the
   handover `.desktop` there.
6. If `$SUDO_USER` is set: mirror autostart + Desktop, `chown`, run `oem-first-run.sh`.

## Uninstall counterpart

`step_uninstall` purges **`plank`**, removes **`/usr/share/backgrounds/oem-setup`**
and **`oem-first-run.sh`**, **`oem-prepare-shipping`**, the handover `.desktop`
files, cleans **`/etc/skel`** and per-user Plank / marker / Desktop launcher
files. **`oem-config` / `oem-config-gtk`** are purged together with the other
toolkit packages in the apt purge list.
See [`uninstall.md`](../uninstall.md).
