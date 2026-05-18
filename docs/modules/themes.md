# `modules/themes.sh`

## Purpose

Deploys **Plank**, the **Malta** OEM wallpaper, the per-user **`oem-first-run.sh`**
helper, and the **`skel/`** autostart entries. **`oem-config`** /
**`oem-config-gtk`** are **not** installed by this toolkit — they are pulled in
when you run **`oem-prepare-shipping.sh`** before handover. That script is **not**
deployed by this module (operators run it separately from the repo or GitHub).

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
- `$REPO_DIR/skel/.` (typically `autostart`)
- `ensure_apt_fresh` (for apt installs)
- `$SUDO_USER` — when set, mirrors skel **autostart** into the live session and
  runs `oem-first-run.sh` inline

## Outputs

- **apt:** `plank`
- **`/usr/share/backgrounds/oem-setup/malta.jpg`**
- **`/usr/local/bin/oem-first-run.sh`** (mode `755`)
- **`/etc/skel/...`** — copy of repo `skel/`
- **Live session:** copies autostart `.desktop` files into `$SUDO_HOME`, then runs
  `oem-first-run.sh`

## Walkthrough

1. `ensure_apt_fresh` then `apt-get install -y plank`.
2. Copy wallpaper into `/usr/share/backgrounds/oem-setup/`.
3. Install `oem-first-run.sh` to `/usr/local/bin/`.
4. `cp -r "$REPO_DIR/skel/." /etc/skel/`.
5. If `$SUDO_USER` is set: mirror autostart, `chown`, run `oem-first-run.sh`.

## Uninstall counterpart

`step_uninstall` purges **`plank`**, removes **`/usr/share/backgrounds/oem-setup`**
and **`oem-first-run.sh`**, **best-effort** cleanup of legacy **`oem-prepare-shipping`**
binaries / handover **`.desktop`** files (from older toolkit revisions), cleans
**`/etc/skel`** and per-user Plank / marker / Desktop launcher files.
**`oem-config` / `oem-config-gtk`** are also on the **`step_uninstall`** apt purge
list (no-ops if never installed).

See [`uninstall.md`](../uninstall.md).
