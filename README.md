# linux-oem-setup-utils

Modular provisioning toolkit for **refurbished Chromebooks** (AMD/Intel, 4GB RAM) running **Lubuntu**. Scripts are idempotent, system-wide (`/etc/skel`, `/etc/xdg`, `/usr/share/applications`), and safe to re-run.

Target environment: **Lubuntu 26.04 LTS (Resolute)** and compatible releases (LXQt / Openbox).

## Quick start

On the OEM machine (as root):

```bash
wget -qO- https://raw.githubusercontent.com/olivencencius/linux-oem-setup-utils/main/bootstrap.sh | sudo bash
```

Bootstrap downloads modules into `/tmp/lubuntu-oem-setup`, logs to `/var/log/lubuntu_oem_setup.log`, tracks progress in `/var/lib/lubuntu-oem-setup/.state`, and offers:

- **0** — Full pipeline (modules 1–13 and **15**)
- **1–13**, **15** — Individual module (no module 14)
- **d** — Hardware diagnostics (read-only add-on)
- **h** — Prepare for OEM shipping (disables SDDM, runs `oem-config-prepare`, shuts down)
- **q** — Quit

Resume after interruption: run bootstrap again; completed steps are skipped automatically.

> **Note:** Bootstrap always pulls scripts from the `main` branch on GitHub. Push local changes before using the wget one-liner on another machine.

## Modules

| # | Script | Purpose |
|---|--------|---------|
| 1 | `01_update_os.sh` | `apt-get update` + `upgrade`; `ubuntu-restricted-extras` (codecs & fonts) |
| 2 | `02_install_git.sh` | Install git |
| 3 | `03_boot_optimization.sh` | Mask network wait-online services (offline boot hangs) |
| 4 | `04_chromebook_fixes.sh` | Audio + keyboard (interactive); TLP; ZRAM; swappiness |
| 5 | `05_touchpad_gestures.sh` | libinput touchpad settings + 3-finger workspace swipes |
| 6 | `06_workspaces_view.sh` | skippy-xd + daemon; fixes Lubuntu shortcuts → **`Exec=/usr/bin/skippy-xd, --paging`** (LXQt comma syntax, not shell) |
| 7 | `07_terminal_paste_fix.sh` | Disable bracketed paste in `/etc/inputrc` |
| 8 | `08_install_chrome.sh` | Google Chrome `.deb` |
| 9 | `09_install_vlc.sh` | VLC |
| 10 | `10_web_apps.sh` | Chrome `--app` shortcuts with self-hosted SVG icons |
| 11 | `11_install_games.sh` | supertuxkart, aisleriot, gnome-mines |
| 12 | `12_install_plank.sh` | Plank dock + move LXQt panel to top (`/etc/skel`) |
| 13 | `13_touchpad_scroll_speed.sh` | Slower two-finger scroll via `ScrollPixelDistance` (default **30**, range 10–50; higher = slower) |
| 15 | `15_lid_close_suspend.sh` | Deep sleep (`mem_sleep=deep` when s2idle available) + systemd-logind suspend on lid close |

Modules **4**, **5**, and **6** apply settings to the technician account (`$SUDO_USER`) for QA when run with `sudo`. Module **13** also tries a live `xinput` preview on the technician session. New customer accounts inherit defaults from `/etc/skel`.

Run module 13 alone (after push or from a local clone):

```bash
sudo STATE_DIR=/var/lib/lubuntu-oem-setup STATE_FILE=/var/lib/lubuntu-oem-setup/.state \
  bash modules/13_touchpad_scroll_speed.sh
```

Tune scroll: `sudo OEM_TOUCHPAD_SCROLL_PIXEL_DISTANCE=40 bash modules/13_touchpad_scroll_speed.sh` (safe to re-run; higher = slower, max 50).

## Add-ons

| Script | Purpose |
|--------|---------|
| `addons/diagnostics.sh` | Read-only report: OS, CPU, RAM, ZRAM/swap, storage, battery, network, USB, audio |
| `addons/oem_handover.sh` | Final shipping prep: `oem-config.target`, stop/disable SDDM, `oem-config-prepare`, shutdown |

Run from the bootstrap menu (**d** / **h**) or directly:

```bash
sudo bash addons/diagnostics.sh
sudo bash addons/oem_handover.sh   # confirms, then shuts down
```

## OEM install vs this toolkit

On a **fresh OEM image** (even before bootstrap):

- **First reboot** often **auto-logs the OEM user straight to the desktop** (one-time setup flow).
- **Second reboot** usually shows the normal **SDDM login screen**.

If the session/layout bar appears but the **username/password panel does not**, that can happen **without running this repo** — it is tied to the OEM/SDDM lifecycle, not `keyd` or the bootstrap modules. Do **not** mask/disable `keyd` for that; module 4’s keyboard map should stay as `cros-keyboard-map` installed it.

If you need a login UI workaround on the bench, try the **breeze** SDDM theme (`sddm-theme-breeze` + `Current=breeze` in `/etc/sddm.conf.d/`) — that is an image/greeter issue, not part of the pipeline.

## Handover

Before shipping:

1. Run the full pipeline (or all modules you need).
2. Reboot and verify panel position, Plank dock, overview keys, gestures, web apps, and lid-close suspend.
3. Run diagnostics (**d**) and keep the output for your records if useful.
4. Run **Prepare for OEM shipping** (**h**) or `sudo bash addons/oem_handover.sh`.

   This sets `oem-config.target` as the default boot target, stops and disables SDDM (avoids the blank login screen that races ahead of the first-boot account wizard), runs `oem-config-prepare`, and shuts down. On the customer’s first boot, Calamares walks them through account creation; they inherit `/etc/skel` defaults (panel, Plank, hotkeys, autostart entries).

5. Optionally scrub bootstrap footprints on the bench before handover if you are not using **h**:

   ```bash
   sudo rm -rf /var/lib/lubuntu-oem-setup /tmp/lubuntu-oem-setup
   sudo rm -f /var/log/lubuntu_oem_setup.log
   sudo apt-get clean
   ```

After module **4**, confirm ZRAM is active (`zramctl` / `swapon --show`) — settings may require a reboot if hot-start did not apply on an already-running system.

## Logs & state

- Log: `/var/log/lubuntu_oem_setup.log`
- State: `/var/lib/lubuntu-oem-setup/.state`
- Clear state to force re-run: `sudo rm -f /var/lib/lubuntu-oem-setup/.state`

## Tip — OEM login behaviour

On a **fresh OEM image**, the **first reboot** often auto-logs the OEM user straight to the desktop. The **second reboot** shows the normal **SDDM** login screen. If the session/layout bar appears but the **username/password panel** is missing, that is usually the OEM/SDDM greeter (not fixed by masking `keyd` or by this bootstrap).

**Bench recovery:** switch to a text console with **Ctrl+Alt+F3**, log in with your OEM account, then:

```bash
sudo systemctl restart sddm
```

Switch back to the graphical greeter with **Ctrl+Alt+F1** or **F7**. If SDDM is still unusable, stay on TTY3 and start the session manually (e.g. `startlxqt`) while you fix the image or complete handover.
