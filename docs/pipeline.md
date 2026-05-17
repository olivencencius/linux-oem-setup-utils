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
    run_step hardware_fixes
    run_step xubuntu_boot
    run_step chrome
    run_step zoom
    run_step apps
    run_step web_apps
    run_step gestures_and_workspaces
    run_step themes
    run_step touchpad
    run_step terminal
    run_step regional
    run_step diagnostics
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
half-extracted tree from a failed run can confuse the installer's
overwrite logic; a `wget` to an already-existing `.deb` path is
harmless but a leftover unzipped tree is not.

### 3. `updates` — before anything depends on apt

Runs `apt-get update`, `apt-get upgrade`, then installs `git`, `wget`,
`curl`, `xinput`, `gimp`, `zram-tools`, `tlp`. Multimedia codecs are
**not** installed here — use the OS installer / image options for that.
`step_updates` exports `OEM_APT_FRESH=1` so later modules'
`ensure_apt_fresh` calls become no-ops — one `apt-get update` per pipeline.

`xinput` is installed here so `step_touchpad` can push live values via
`xinput set-prop` without needing its own apt install.

### 4. `hardware_fixes` — before themes/touchpad so a reboot affects everything

Three concerns, all board-specific:

- **Audio** — clones and runs
  `WeirdTreeThing/chromebook-linux-audio`. **This installer may ask
  questions.** It is run under **`oem_run_interactive`** (real TTY on fd 3)
  so the technician can answer even when launched via `curl … | sudo bash`.
- **Top-row keys** — clones and runs
  `WeirdTreeThing/cros-keyboard-map`. Same **`oem_run_interactive`**
  plumbing; same "answer the prompts" expectation.
- **Board patches** — DMI-detected:
  - CELES (Samsung Celes-based boards) → inject
    `clocksource=hpet hpet=force` into `GRUB_CMDLINE_LINUX_DEFAULT`,
    `update-grub`.
  - TigerLake / AlderLake CPU → append `cros-ec-typec` and
    `intel-pmc-mux` to `/etc/initramfs-tools/modules`,
    `update-initramfs -u -k all`.

  Both mutations call `backup_once` first so the originals are
  restored cleanly by `step_uninstall`.

### 4b. `xubuntu_boot` — immediately after hardware (boot polish)

Applies **systemd** tuning (ModemManager off, `NetworkManager-wait-online`
masked, snapd units disabled when present) and **GRUB** silent-boot kernel
parameters, installs/configures **Plymouth** when available, and documents reboot for
full effect. This follows `hardware_fixes` so **CELES HPET** edits and boot-time
kernel tokens land on the same `GRUB_CMDLINE_LINUX_DEFAULT` line without needing
manual ordering.

### 5–8. `chrome`, `zoom`, `apps`, `web_apps` — *before* `themes`

Order is critical. `step_themes` deploys `oem-first-run.sh`, which on
first XFCE login walks a fixed launcher list and adds one Plank
launcher (dockitem) per `/usr/share/applications/NAME.desktop` that
exists. Anything missing at first-login time is silently skipped — the
dock is just short by that icon. So:

- Chrome's `.deb` ships `/usr/share/applications/google-chrome.desktop`.
- Zoom's `.deb` ships `/usr/share/applications/Zoom.desktop`.
- VLC (from `step_apps`) ships `/usr/share/applications/vlc.desktop`.
- The 13 web-app `.desktop` files are created by `step_web_apps`.

If any of those is missing when `oem-first-run.sh` runs, the Plank dock for
that user is short by an icon. (For the live oem user, `step_themes`
runs `oem-first-run.sh` inline at the end of the install — same
guarantee.)

The **workspace overview** launcher (`oem-workspace-overview.desktop`, running
`xfdashboard`) is installed in **`step_gestures_and_workspaces`**, which runs
**next**, so that `.desktop` exists before `step_themes` invokes
`oem-first-run.sh`.

Zoom is allowed to fail. Its CDN is occasionally flaky and Zoom is
"nice to have", not "must ship". The module returns 0 in that case,
`/usr/share/applications/Zoom.desktop` won't exist, and
`oem-first-run.sh` simply omits the Zoom launcher from the dock. The
technician sees a `[!] Zoom .deb download failed — skipping.` line in
the log.

### 9. `gestures_and_workspaces` — after web apps, before themes

Installs **`wmctrl`**, **`xdotool`**, **`libinput-tools`**, **`python3`**, **`git`**,
then clones **bulletmark/libinput-gestures** under `/var/cache/oem-setup/` and runs
**`libinput-gestures-setup install`**. Overwrites **`/etc/libinput-gestures.conf`**
with the bundled ChromeOS-like profile from **`assets/`**, installs
**`/etc/xdg/autostart/libinput-gestures.desktop`** so **every graphical user session**
runs gestures, merges **`input`** into the last **`EXTRA_GROUPS=`** line in
`/etc/adduser.conf`, and attaches existing normal users (**uid ≥ 1000**) to the
 **`input`** group. Deploys **`/usr/share/applications/oem-workspace-overview.desktop`**;
installs **`xfdashboard`**, **`rofi`**, and **`/usr/local/bin/oem-add-workspace.sh`**.
Attempts **`libinput-gestures`** in the running session
when `$SUDO_USER` is set and already in **`input`** (otherwise a full re-login /
reboot is required). Legacy **`touchegg`** Debian packages/services are disabled
and purged during this step.

This step is deliberately **before** `themes` so `oem-first-run.sh` can pin the
overview icon when it seeds Plank.

### 10. `themes` — wallpaper, Plank, panel layout, OEM handover

Installs **`plank`**, **`oem-config`**, **`oem-config-gtk`**, deploys the Malta
wallpaper, **`oem-prepare-shipping`**, the **`oem-prepare-shipping.desktop`**
launcher (system menu + `/etc/skel/Desktop/`), deploys and stages the
per-user first-run script, and copies the **`skel/`** tree (autostart entries
only — no forced GTK/icon themes). For the live technician session it mirrors
autostart and **Desktop** into that user's home and runs `oem-first-run.sh` inline to
apply the wallpaper, top panel layout (including workspace **pager** when missing), **xfwm4** workspace defaults, keyboard bindings for **rofi** / **add workspace**, and bottom Plank dock immediately.
See [`modules/themes.md`](./modules/themes.md) for the detail.

GTK and icon themes stay at **distro defaults** (**Xubuntu**).

### 11. `touchpad` — after themes

Writes `/etc/X11/xorg.conf.d/40-chromebook-touchpad.conf` with
`NaturalScrolling`, `Tapping`, `TappingDrag`, `ClickMethod clickfinger`,
`DisableWhileTyping`, and `ScrollPixelDistance=40` (libinput's default
is ~15; higher = slower scroll, which is the OEM-desired feel). The same
values are pushed to the live session via `xinput set-prop` (including
tapping and clickfinger) so the technician feels the behaviour during QA
without needing an X restart.

The previous revision wired up an `imwheel`-based 3x scroll
*multiplier* in this step. That made scrolling *faster* than default
— the opposite of what the workflow wants — and has been removed.
`step_uninstall` still purges `imwheel` and the per-user `.imwheelrc`
to clean up legacy installs.

### 12. `terminal` — tiny, before regional

Disables bracketed paste mode in `/etc/inputrc` and `/etc/skel/.inputrc`.
Cheap.

### 13. `regional` — after the apt-fresh modules are done

Installs language packs (`-pl`, `-gnome-pl`, `-en`, `-gnome-en`),
generates locales, sets `LANG=pl_PL.UTF-8`, timezone `Europe/Warsaw`,
and the chosen `XKBLAYOUT`. Because this runs late, the language packs
do not slow down apt during the earlier package-heavy steps.

### 14. `diagnostics` — last

Runs **`step_diagnostics`** (`modules/diagnostics.sh`): a read-only inventory and
automated `[PASS]`/`[WARN]`/`[FAIL]` report so technicians see system state and
common misconfiguration hints immediately after every other step has run.
Keeping it last ensures the report reflects the deployed wallpaper, web apps,
touchpad snippet, `libinput-gestures`, ZRAM, TLP, keyboard/audio stack, **and boot timing**
(`systemd-analyze` excerpts under **Boot (systemd)**) as left by earlier steps. The script never prompts and never raises —
manual QA remains in [`handover-qa.md`](./handover-qa.md).

## What is **not** in the pipeline

- **`uninstall`** is only reachable via menu option `15`. It is sourced
  by `setup.sh` like every other module but never called from
  `run_full_pipeline`.
- **`cleanup` is repeated**: `step_uninstall` calls `step_cleanup` near
  the end to scrub `/tmp` again before exit.

## What still requires a reboot after the pipeline

`print_reboot_reminder` (printed automatically) covers the user-visible
case. The actual list:

- GRUB boot parameters and Plymouth from **`step_xubuntu_boot`** (also in the
  default pipeline, and re-runnable via **menu option `2`**) — reboot recommended.
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

| Concern | Full pipeline (`1`) | Individual options (`3`–`14`) |
|---|---|---|
| Step wrapper | `run_step` (skip if done) | `do_step` (always run) |
| Resume after crash | yes — finished steps skipped | n/a (technician picks what to run) |
| `apt-get update` | once, in `step_updates` | `ensure_apt_fresh` runs it once per session |
| Keyboard prompt | once, at the start | only when option 13 is picked stand-alone |
| Reboot reminder | printed automatically | not printed |
| `step_cleanup` | runs once, early | options 3, 4, 9 chain it before their main step |

For the option-15 (uninstall) flow see [`uninstall.md`](./uninstall.md).
