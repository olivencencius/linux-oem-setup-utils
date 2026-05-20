# linux-oem-setup-utils

Modular provisioning toolkit for **refurbished Chromebooks** (AMD/Intel, 4GB RAM) running **Xubuntu**. Scripts are idempotent, system-wide (`/etc/skel`, `/etc/xdg`, `/usr/share/applications`), and safe to re-run.

## Quick start

On the OEM machine (as root):

```bash
wget -qO- https://raw.githubusercontent.com/olivencencius/linux-oem-setup-utils/main/bootstrap.sh | sudo bash
```

Bootstrap downloads modules into `/tmp/xubuntu-oem-setup`, logs to `/var/log/xubuntu_oem_setup.log`, tracks progress in `/var/lib/xubuntu-oem-setup/.state`, and offers:

- **0** — Full pipeline (modules 1–12)
- **1–12** — Individual module
- **q** — Quit

Resume after interruption: run bootstrap again; completed steps are skipped automatically.

## Modules

| # | Script | Purpose |
|---|--------|---------|
| 1 | `01_update_os.sh` | `apt-get update` + `upgrade` |
| 2 | `02_install_git.sh` | Install git |
| 3 | `03_boot_optimization.sh` | Mask network wait-online; quiet GRUB |
| 4 | `04_chromebook_fixes.sh` | Audio + keyboard (interactive), zram, tlp, swappiness |
| 5 | `05_touchpad_gestures.sh` | libinput touchpad + touchegg workspace swipes |
| 6 | `06_workspaces_view.sh` | xfdashboard + overview key bindings |
| 7 | `07_terminal_paste_fix.sh` | Disable bracketed paste in `/etc/inputrc` |
| 8 | `08_install_chrome.sh` | Google Chrome `.deb` |
| 9 | `09_install_vlc.sh` | VLC |
| 10 | `10_web_apps.sh` | Chrome `--app` shortcuts (keyring bypass) |
| 11 | `11_install_games.sh` | supertuxkart, aisleriot, gnome-mines |
| 12 | `12_install_plank.sh` | Plank dock in `/etc/skel` |

## Add-ons

| Script | Purpose |
|--------|---------|
| `addons/diagnostics.sh` | Read-only CPU/RAM/battery/USB/audio report |
| `addons/prepare_for_shipping.sh` | `oem-config-prepare` for end-user first boot |

Run add-ons directly (not part of the default menu):

```bash
sudo bash addons/diagnostics.sh
sudo bash addons/prepare_for_shipping.sh
```

## Handover

1. Run the full pipeline (or all modules you need).
2. Reboot and verify dock, gestures, and web apps.
3. Run `addons/prepare_for_shipping.sh` before shipping.
4. On first customer boot, they create their account and inherit `/etc/skel` defaults.

## Logs & state

- Log: `/var/log/xubuntu_oem_setup.log`
- State: `/var/lib/xubuntu-oem-setup/.state`
- Clear state to force re-run: `sudo rm -f /var/lib/xubuntu-oem-setup/.state`

## License

See repository license file if present.
