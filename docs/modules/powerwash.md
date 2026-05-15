# `modules/powerwash.sh`

## Purpose

Installs the buyer-facing **Powerwash** (factory reset) feature. This
is just the *installation* step — see [`../powerwash.md`](../powerwash.md)
for the end-to-end flow of what happens when the buyer actually
launches it.

## Function exported

`step_powerwash`

## Inputs

- `ensure_apt_fresh` (helper from `setup.sh`).
- `$REPO_DIR/assets/scripts/oem-powerwash{.sh,-arm.sh,-finalize.sh}` —
  the three shell scripts.
- `$REPO_DIR/assets/configs/oem-powerwash{.desktop,.policy,-finalize.service}`
  — the three system config files.
- `$REPO_DIR/assets/icons/oem-powerwash.svg` — the menu/polkit icon.

## Outputs

Installed packages:

- `zenity` — used by `oem-powerwash.sh` for the GUI confirmation
  dialogs.
- `policykit-1` — provides `pkexec` and the polkit auth dialog.
- `oem-config-gtk` — provides `oem-config-prepare` (the command
  `oem-powerwash-finalize.sh` calls to re-arm the wizard) and the
  GTK first-boot wizard the buyer is sent back to.

System files installed (each from a corresponding `assets/` source):

| Destination | Mode | Source |
|---|---|---|
| `/usr/local/bin/oem-powerwash.sh` | `755` | `assets/scripts/oem-powerwash.sh` |
| `/usr/local/sbin/oem-powerwash-arm.sh` | `700` | `assets/scripts/oem-powerwash-arm.sh` |
| `/usr/local/sbin/oem-powerwash-finalize.sh` | `700` | `assets/scripts/oem-powerwash-finalize.sh` |
| `/etc/systemd/system/oem-powerwash-finalize.service` | `644` | `assets/configs/oem-powerwash-finalize.service` |
| `/usr/share/applications/oem-powerwash.desktop` | `644` | `assets/configs/oem-powerwash.desktop` |
| `/usr/share/polkit-1/actions/org.linuxoem.powerwash.policy` | `644` | `assets/configs/oem-powerwash.policy` |
| `/usr/share/icons/hicolor/scalable/apps/oem-powerwash.svg` | (cp default) | `assets/icons/oem-powerwash.svg` |

Also: created directory `/var/lib/oem-setup/` (so the arm script can
later write the flag there).

Services touched:

- `systemctl daemon-reload` to register the new unit.
- `systemctl disable oem-powerwash-finalize.service` so it stays
  inert until armed.

Caches refreshed:

- `gtk-update-icon-cache -f -t /usr/share/icons/hicolor`.
- `update-desktop-database /usr/share/applications`.

## Walkthrough

```bash
ensure_apt_fresh
apt-get install -y zenity policykit-1 oem-config-gtk

install -m 755 "$REPO_DIR/assets/scripts/oem-powerwash.sh"          /usr/local/bin/oem-powerwash.sh
install -m 700 "$REPO_DIR/assets/scripts/oem-powerwash-arm.sh"      /usr/local/sbin/oem-powerwash-arm.sh
install -m 700 "$REPO_DIR/assets/scripts/oem-powerwash-finalize.sh" /usr/local/sbin/oem-powerwash-finalize.sh

install -m 644 "$REPO_DIR/assets/configs/oem-powerwash-finalize.service" \
               /etc/systemd/system/oem-powerwash-finalize.service
systemctl daemon-reload
systemctl disable oem-powerwash-finalize.service 2>/dev/null || true

mkdir -p /usr/share/icons/hicolor/scalable/apps
cp "$REPO_DIR/assets/icons/oem-powerwash.svg" /usr/share/icons/hicolor/scalable/apps/oem-powerwash.svg
gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true

install -m 644 "$REPO_DIR/assets/configs/oem-powerwash.desktop" /usr/share/applications/oem-powerwash.desktop
update-desktop-database /usr/share/applications 2>/dev/null || true

mkdir -p /usr/share/polkit-1/actions
install -m 644 "$REPO_DIR/assets/configs/oem-powerwash.policy" \
               /usr/share/polkit-1/actions/org.linuxoem.powerwash.policy

mkdir -p /var/lib/oem-setup
```

Sequential and conservative. Note the **modes**:

- `755` for `oem-powerwash.sh` — the buyer runs it, so it must be
  world-executable.
- `700` for both `sbin` scripts — only root can read or execute them
  directly. The polkit policy whitelists the arm script as a pkexec
  target, but a privileged buyer cannot read the script's source code
  to copy-paste arguments. Defence in depth.
- `644` for the three config files (systemd unit, polkit policy,
  desktop entry) — read-only for non-root, which is what their
  consumers expect.

The `systemctl disable` after the daemon-reload is on purpose: the
unit's `[Install] WantedBy=multi-user.target` would otherwise let any
`systemctl enable` immediately stage it for next boot. We keep it
*disabled* until the arm script explicitly enables it.

## Notes

- This module **does not** ever enable the finalize service. That's
  the arm script's job, gated by polkit + two zenity confirmations.
- `oem-config-gtk` is the heaviest dependency installed here. Most
  Mint OEM images already ship with it, but adding it as an explicit
  dependency means a non-OEM-image Mint install can also use the
  Powerwash feature.
- The `2>/dev/null || true` on the cache refreshes is defensive —
  some Mint versions return non-zero from up-to-date cache calls.

## Idempotency

Fully idempotent:

- `apt-get install -y` is a no-op for installed packages.
- `install -m … src dst` overwrites with identical content.
- `cp` overwrites.
- `systemctl daemon-reload` is always safe.
- `systemctl disable` of an already-disabled unit is a no-op.

## Uninstall counterpart

`step_uninstall` sub-step 8b dedicates an entire block to Powerwash:

```bash
systemctl disable oem-powerwash-finalize.service
rm /etc/systemd/system/oem-powerwash-finalize.service
systemctl daemon-reload
rm /usr/local/bin/oem-powerwash.sh
rm /usr/local/sbin/oem-powerwash-arm.sh
rm /usr/local/sbin/oem-powerwash-finalize.sh
rm /usr/share/applications/oem-powerwash.desktop
rm /usr/share/icons/hicolor/scalable/apps/oem-powerwash.svg
rm /usr/share/polkit-1/actions/org.linuxoem.powerwash.policy
rm /var/lib/oem-setup/powerwash.flag      # if a pending arm exists
rm /var/log/oem-powerwash.log
update-desktop-database /usr/share/applications
```

`zenity`, `policykit-1` and `oem-config-gtk` are intentionally **not**
purged — they are commonly part of the Mint OEM image already and
removing them risks breaking the system.

## See also

- [`../powerwash.md`](../powerwash.md) — the cross-cutting deep-dive
  on the entire Powerwash flow (menu → polkit → arm → boot finalize).
- [`../assets.md`](../assets.md) — install-path map for every asset
  this module touches.
