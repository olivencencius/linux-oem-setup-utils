# linux-oem-setup-utils

Modular provisioning toolkit for **refurbished Chromebooks** (AMD/Intel, 4GB RAM) running **Lubuntu**. Scripts are idempotent, system-wide (`/etc/skel`, `/etc/xdg`, `/usr/share/applications`), and safe to re-run.

Target environment: **Lubuntu 26.04 LTS (Resolute)** and compatible releases (LXQt / Openbox).

## Quick start

On the OEM machine (as root):

```bash
wget -qO- https://raw.githubusercontent.com/olivencencius/linux-oem-setup-utils/main/bootstrap.sh | sudo bash
```

Bootstrap downloads modules into `/tmp/lubuntu-oem-setup`, logs to `/var/log/lubuntu_oem_setup.log`, tracks progress in `/var/lib/lubuntu-oem-setup/.state`, and offers:

- **0** — Full pipeline (modules 1–13)
- **1–13** — Individual module
- **d** — Hardware diagnostics (read-only add-on)
- **q** — Quit

Resume after interruption: run bootstrap again; completed steps are skipped automatically.

> **Note:** Bootstrap always pulls scripts from the `main` branch on GitHub. Push local changes before using the wget one-liner on another machine.

## Modules

| # | Script | Purpose |
|---|--------|---------|
| 1 | `01_update_os.sh` | `apt-get update` + `upgrade`; `ubuntu-restricted-extras` (codecs & fonts) |
| 2 | `02_install_git.sh` | Install git |
| 3 | `03_boot_optimization.sh` | Mask network wait-online services (offline boot hangs) |
| 4 | `04_chromebook_fixes.sh` | Audio + keyboard (interactive); TLP; ZRAM via `systemd-zram-generator`; swappiness |
| 5 | `05_touchpad_gestures.sh` | libinput touchpad settings + 3-finger workspace swipes |
| 6 | `06_workspaces_view.sh` | skippy-xd (built from upstream; not in apt on 26.04) + daemon autostart + LXQt overview keys (`--paging`; Chromebook launcher: `XF86LaunchA`) |
| 7 | `07_terminal_paste_fix.sh` | Disable bracketed paste in `/etc/inputrc` |
| 8 | `08_install_chrome.sh` | Google Chrome `.deb` |
| 9 | `09_install_vlc.sh` | VLC |
| 10 | `10_web_apps.sh` | Chrome `--app` shortcuts with self-hosted SVG icons |
| 11 | `11_install_games.sh` | supertuxkart, aisleriot, gnome-mines |
| 12 | `12_install_plank.sh` | Plank dock + move LXQt panel to top (`/etc/skel`) |
| 13 | `13_touchpad_scroll_speed.sh` | Slower two-finger touchpad scroll via libinput `ScrollFactor` (does not change pointer speed) |

Modules **4**, **5**, and **6** apply settings to the technician account (`$SUDO_USER`) for QA when run with `sudo`. Module **13** also tries a live `xinput` preview on the technician session. New customer accounts inherit defaults from `/etc/skel`.

Run module 13 alone (after push or from a local clone):

```bash
sudo STATE_DIR=/var/lib/lubuntu-oem-setup STATE_FILE=/var/lib/lubuntu-oem-setup/.state \
  bash modules/13_touchpad_scroll_speed.sh
```

Tune scroll strength without editing the file: `sudo OEM_TOUCHPAD_SCROLL_FACTOR=0.3 bash modules/13_touchpad_scroll_speed.sh` (clear module **13** from `.state` first if it already completed).

## Add-ons

| Script | Purpose |
|--------|---------|
| `addons/diagnostics.sh` | Read-only report: OS, CPU, RAM, ZRAM/swap, storage, battery, network, USB, audio |

Run from the bootstrap menu (**d**) or directly:

```bash
sudo bash addons/diagnostics.sh
```

## Handover

Lubuntu has no Ubuntu OEM / `oem-config-prepare` flow. Before shipping:

1. Run the full pipeline (or all modules you need).
2. Reboot and verify panel position, Plank dock, overview keys, gestures, and web apps.
3. Run diagnostics (**d**) and keep the output for your records if useful.
4. Remove the technician account (or reset the machine to a clean state).
5. Scrub OEM footprints:

   ```bash
   sudo rm -rf /var/lib/lubuntu-oem-setup /tmp/lubuntu-oem-setup
   sudo rm -f /var/log/lubuntu_oem_setup.log
   sudo apt-get clean
   ```

6. On first customer boot, they create their account and inherit `/etc/skel` defaults (panel, Plank, hotkeys, autostart entries).

After module **4**, confirm ZRAM is active (`zramctl` / `swapon --show`) — settings may require a reboot if hot-start did not apply on an already-running system.

## Logs & state

- Log: `/var/log/lubuntu_oem_setup.log`
- State: `/var/lib/lubuntu-oem-setup/.state`
- Clear state to force re-run: `sudo rm -f /var/lib/lubuntu-oem-setup/.state`
