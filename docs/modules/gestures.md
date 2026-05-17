# `modules/gestures.sh`

## Purpose

Installs **`libinput-gestures`** (bulletmark/upstream Git clone →
`./libinput-gestures-setup install`), deploys **`/etc/libinput-gestures.conf`**
from **`$REPO_DIR/assets/configs/libinput-gestures.conf`** (ChromeOS-like
bindings: pinch zoom, 3- and 4-finger swipes, `xfdashboard` / Whisker /
workspaces). Also installs **`xfdashboard`**, **`rofi`**, **`oem-add-workspace.sh`**
(**`/usr/local/bin`**), publishes
**`/usr/share/applications/oem-workspace-overview.desktop`** for Plank.

Runs **before** `step_themes` so `oem-first-run.sh` can seed a dock item for
workspace overview while `xfdashboard` is already installed.

## Function exported

`step_gestures_and_workspaces`

## Inputs / environment

- `ensure_apt_fresh`, `backup_once` (from `setup.sh`).
- `LIBINPUT_GESTURES_GIT_REF` — optional; default clones
  **`https://github.com/bulletmark/libinput-gestures.git`** (`master`).
- `$REPO_DIR/assets/configs/libinput-gestures.conf`.
- `$REPO_DIR/assets/configs/oem-workspace-overview.desktop`.
- `$REPO_DIR/assets/scripts/oem-add-workspace.sh`.
- `$SUDO_USER` — when set, tries to spawn `/usr/bin/libinput-gestures`
  for the running X session once the **`input`** group is effective.

## Outputs

APT packages:`python3`, `libinput-tools`, `wmctrl`, `xdotool`, `xfdashboard`, `rofi`, `git`.

Upstream installs (paths from `libinput-gestures-setup install`):

- `/usr/bin/libinput-gestures`, `/usr/bin/libinput-gestures-setup`
- `/usr/share/applications/libinput-gestures.desktop` (upstream)

OEM overlays:

- `/etc/libinput-gestures.conf` — toolkit binding profile (`install -m 644`).
- **`/usr/local/bin/oem-add-workspace.sh`** — increments **`xfwm4`** workspace count
  (bound **Super+Insert** on first login by **`oem-first-run.sh`**).
- **`/etc/xdg/autostart/libinput-gestures.desktop`** — copy of upstream’s desktop
  file so **every XFCE user session** autostarts gestures (buyer accounts
  included).

Group policy (needed because libinput-gestures must read the touchpad device):

1. **`/etc/adduser.conf`** — the **last** `EXTRA_GROUPS="…"` line gains a
   trailing **`input`** membership for **future** `adduser` accounts.
2. **`usermod -a -G input`** for existing human users (**uid ≥ 1000**, **< 65534**).

Installer also **purges legacy `touchegg`** (Debian/apt package), disables
 **`touchegg.service`** if present, and deletes **`/etc/touchegg/`** so older
profiles cannot collide.

## Uninstall alignment

Handled in `step_uninstall`: `libinput-gestures-setup uninstall`, remove OEM
`/etc/xdg/autostart` copy + clone cache under `/var/cache/oem-setup/`,
`restore_or_skip /etc/adduser.conf` when a first-run backup exists, scrub
`/etc/libinput-gestures.conf` leftovers, **`apt purge`** **`rofi`** with other
gesture-related packages, **`rm /usr/local/bin/oem-add-workspace.sh`**, **`apt purge touchegg`** (legacy).

Supplemental group **`input`** on existing user accounts is **not** stripped
(best-effort note in uninstall summary).

## Idempotency / upgrades

If **`/usr/bin/libinput-gestures`** is missing (fresh image or failed prior
run) but a stale **`gestures_and_workspaces.done`** marker exists, the step
**deletes** that marker (and legacy **`gestures.done`**) so the pipeline cannot
skip the upstream install — older releases used Touchegg instead.
