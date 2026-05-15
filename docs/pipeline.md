# Pipeline

This page documents what the full pipeline (menu option `1`) does, in
order, and *why* each step is where it is. For the *how* of one
particular step, see [`modules/`](./modules/).

## The function

```bash
run_full_pipeline() {
    prompt_keyboard
    run_step cleanup
    run_step updates
    run_step flathub
    run_step hardware_fixes
    run_step chrome
    run_step zoom
    run_step apps
    run_step web_apps
    run_step themes
    run_step touchpad
    run_step gestures
    run_step terminal
    run_step regional
    run_step powerwash
}
```

Each `run_step` skips if `/var/lib/oem-setup/state/<name>.done` exists, so
a re-run after a crash resumes from the failed step. See
[`architecture.md`](./architecture.md) for the state model.

`prompt_keyboard` is **not** wrapped in `run_step` because it does its own
persistence — it writes to `$STATE_DIR/kb_layout` and short-circuits on
re-runs.

## Why this order

### 1. `prompt_keyboard` — first

The pipeline is intended to run mostly unattended. The keyboard prompt
is the one human-blocking interaction we can't push to the end (locale
generation, `setupcon` and `localectl` in `step_regional` all need the
answer). Asking up-front means the technician can walk away after a
single answer.

### 2. `cleanup` — before any download

Removes leftover `/tmp/*.deb` and `/tmp/Chrome*` / `/tmp/Tela*` /
`/tmp/cros-*` directories from a previous partial run. Without this, a
half-extracted theme tree from a failed run can confuse the installer's
overwrite logic; a `wget` to an already-existing `.deb` path is
harmless but a leftover unzipped tree is not.

### 3. `updates` — before anything depends on apt

Runs `apt-get update`, `apt-get upgrade`, then installs `mint-meta-codecs`,
`git`, `wget`, `curl`, `xinput`, `gimp`, `imwheel`, `zram-tools`, `tlp`.
Crucially, `step_updates` exports `OEM_APT_FRESH=1` so later modules'
`ensure_apt_fresh` calls become no-ops — one `apt-get update` per
pipeline.

`imwheel` and `xinput` are installed here so `step_touchpad` doesn't
need to. `gimp` is installed in the base-tools group rather than in
`step_apps` because it's a productivity tool, not a media-player /
game.

### 4. `flathub` — early, low-risk

Adds the Flathub remote. No flatpak app is installed by the toolkit
(apt is preferred to save the ~1.5 GB GNOME/freedesktop runtime on a
4 GB eMMC). The remote is added so the *buyer* can install flatpak apps
later without having to know how to add the remote.

### 5. `hardware_fixes` — before themes/touchpad so a reboot affects everything

Three concerns, all board-specific:

- **Audio** — clones and runs
  `WeirdTreeThing/chromebook-linux-audio`. **This installer may ask
  questions.** Its stdin is wired to `/dev/tty` so the technician can
  answer even when launched via `curl … | sudo bash`.
- **Top-row keys** — clones and runs
  `WeirdTreeThing/cros-keyboard-map`. Same `/dev/tty` plumbing; same
  "answer the prompts" expectation.
- **Board patches** — DMI-detected:
  - CELES (Samsung Celes-based boards) → inject
    `clocksource=hpet hpet=force` into `GRUB_CMDLINE_LINUX_DEFAULT`,
    `update-grub`.
  - TigerLake / AlderLake CPU → append `cros-ec-typec` and
    `intel-pmc-mux` to `/etc/initramfs-tools/modules`,
    `update-initramfs -u -k all`.

  Both mutations call `backup_once` first so the originals are
  restored cleanly by `step_uninstall`.

### 6–9. `chrome`, `zoom`, `apps`, `web_apps` — *before* `themes`

Order is critical. `step_themes` stages dock launchers from `skel/`
into `/etc/skel`. Each dockitem references a `/usr/share/applications/
NAME.desktop` file. Plank reads dockitems at user login and silently
drops any whose referenced `.desktop` is missing. So:

- Chrome's `.deb` ships `/usr/share/applications/google-chrome.desktop`.
- Zoom's `.deb` ships `/usr/share/applications/Zoom.desktop`.
- VLC (from `step_apps`) ships `/usr/share/applications/vlc.desktop`.
- The 11 web-app `.desktop` files are created by `step_web_apps`.

If any of those is missing when `step_themes` copies `/etc/skel`, the
dock for every future user is short by an icon.

Zoom is allowed to fail. Its CDN is occasionally flaky and Zoom is
"nice to have", not "must ship". The module returns 0 in that case,
the dockitem still references `/usr/share/applications/Zoom.desktop`
which won't exist, and Plank will silently skip it — slightly ugly,
but the rest of the dock is still correct. The technician sees a
`[!] Zoom .deb download failed — skipping.` line in the log.

### 10. `themes` — the big one

Pulls together: ChromeOS GTK theme, Tela-blue icons, the Plank dock
binary + config, the wallpaper file, the per-user first-run script,
and the entire `/etc/skel` tree. See
[`modules/themes.md`](./modules/themes.md) for the detail.

This is the step that turns a "Mint XFCE with some apps installed"
into "looks and feels like ChromeOS".

### 11. `touchpad` — after themes (so imwheel uses the skel config)

`skel/.imwheelrc` (the single source of truth for the scroll multiplier)
has been staged into `/etc/skel` by step `themes`. `step_touchpad` then
copies the same file into the live `oem` user's home so the technician
sees 3x scroll *during QA*. The autostart entry that runs imwheel on
each login was also placed in `/etc/skel/.config/autostart/` by
`step_themes`.

The xorg.conf snippet (`40-chromebook-touchpad.conf`) is system-wide
and survives reboot for every user.

### 12. `gestures` — after touchpad

`touchegg` is installed and its system daemon enabled. The
`/etc/touchegg/touchegg.conf` file is deployed from
`assets/configs/`. The skel autostart entry that runs `touchegg --client`
per user has been staged by `step_themes`. `step_gestures` only adds the
live-session client start so the technician can QA gestures.

### 13. `terminal` — tiny, before regional

Disables bracketed paste mode in `/etc/inputrc` and `/etc/skel/.inputrc`.
Cheap.

### 14. `regional` — after the apt-fresh modules are done

Installs language packs (`-pl`, `-gnome-pl`, `-en`, `-gnome-en`),
generates locales, sets `LANG=pl_PL.UTF-8`, timezone `Europe/Warsaw`,
and the chosen `XKBLAYOUT`. Because this runs late, the language packs
do not slow down apt during the earlier package-heavy steps.

### 15. `powerwash` — last

Installs the buyer-facing factory-reset tool: scripts, systemd unit,
polkit policy, menu entry, icon. Last because it's a feature for the
*buyer*, not part of the visible deployment, and only depends on
`zenity` / `policykit-1` / `oem-config-gtk` which it brings in
itself.

## What is **not** in the pipeline

- **`uninstall`** is only reachable via menu option `15`. It is sourced
  by `setup.sh` like every other module but never called from
  `run_full_pipeline`.
- **`cleanup` is repeated**: `step_uninstall` calls `step_cleanup` near
  the end to scrub `/tmp` again before exit.

## What still requires a reboot after the pipeline

`print_reboot_reminder` (printed automatically) covers the user-visible
case. The actual list:

- GRUB kernel command line (CELES HPET fix) — needs reboot.
- initramfs modules (Tiger/AlderLake Type-C fix) — needs reboot.
- chromebook-linux-audio quirks — most are loaded on boot via udev/ALSA
  UCM, so they need a reboot to fully take effect.
- cros-keyboard-map / `keyd` — needs reboot for the daemon to attach
  to the keyboard at the right point in early userspace.
- `XKBLAYOUT` change — applied immediately by `setupcon`, but the
  display manager and any running apps cache the old layout until
  login.
- Locale change — `localectl set-locale` writes `/etc/default/locale`,
  but already-running processes (including the `oem` session) keep the
  old locale until next login.

## Menu vs full pipeline

| Concern | Full pipeline (`1`) | Individual options (`2`–`14`) |
|---|---|---|
| Step wrapper | `run_step` (skip if done) | `do_step` (always run) |
| Resume after crash | yes — finished steps skipped | n/a (technician picks what to run) |
| `apt-get update` | once, in `step_updates` | `ensure_apt_fresh` runs it once per session |
| Keyboard prompt | once, at the start | only when option 13 is picked stand-alone |
| Reboot reminder | printed automatically | not printed |
| `step_cleanup` | runs once, early | options 2, 4, 9 chain it before their main step |

For the option-15 (uninstall) flow see [`uninstall.md`](./uninstall.md).
