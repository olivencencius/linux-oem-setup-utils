# `modules/uninstall.sh`

## Purpose

Best-effort reversal of every change this toolkit makes. Returns the
machine toward a stock **Xubuntu LTS** image state (minus non-apt artefacts and
supplemental **`input`** group memberships the uninstall does not strip).

For the full step-by-step breakdown of *what* gets reverted and the
best-effort caveats, see [`../uninstall.md`](../uninstall.md). This
page documents the module file itself — how it is structured, what
helpers it adds, how it integrates with the rest of the toolkit.

## Function exported

`step_uninstall`

## Helpers defined (file scope)

- `BACKUP_DIR="/var/lib/oem-setup/backups"` — where `backup_once` put
  its snapshots during install.
- `UNINSTALL_NOTES=()` — accumulator for "best-effort caveats", printed
  in the closing summary.
- `note "..."` — appends a single message to `UNINSTALL_NOTES`.
- `restore_or_skip <target>` — restore `<target>` from
  `$BACKUP_DIR/$(basename target)` if present; otherwise return 1 so
  callers can fall back to sed-based line removal.

These are scoped at the file level so they're available throughout
`step_uninstall` without needing to be passed around or re-defined
inside the function.

## Inputs

- `BACKUP_DIR` contents (`/var/lib/oem-setup/backups/`):
  - `grub`
  - `modules` (initramfs-tools)
  - `inputrc`
  - `keyboard`
- `$SUDO_USER` (optional) — used to kill the user's helpers
  (libinput-gestures, xfdashboard, rofi,
  plus legacy imwheel from old
  installs) and to dedupe the per-user cleanup loop.
- `/dev/tty` — the `YES` confirmation prompt reads from it.

## Outputs

Reverts every system-level change the toolkit makes. The ordered list is in [`../uninstall.md`](../uninstall.md).

Headline buckets:

1. Stops services (`tlp`, `touchegg` legacy unit if present, `keyd`) and kills `libinput-gestures`.
2. `apt purge` every Debian package this toolkit installs; autoremove / autoclean (includes legacy **`touchegg`** if apt-installed).
3. Removes the Google Chrome apt repository files and key.
4. Best-effort audio quirk cleanup (note appended).
5. Reverts GRUB (HPET + optional silent-boot tokens), restores boot-related systemd units (NM-wait-online, ModemManager, snapd), reverts initramfs-modules; regenerates boot assets.
6. **`libinput-gestures-setup uninstall`** (when present), remove `/etc/xdg/autostart/libinput-gestures.desktop` + OEM **`/etc/libinput-gestures.conf`**, wipe clone cache, legacy **`/etc/touchegg/`**, touchpad xorg snippet; **`restore_or_skip /etc/adduser.conf`** when snapshots exist.
7. Removes OEM wallpaper dir, `oem-first-run.sh`, `oem-add-workspace.sh`, handover + workspace-overview `.desktop`.
8. Removes web-app `.desktop` files and icons.
9. Reverts terminal `inputrc` changes.
10. Reverts regional settings.
11. Cleans `/etc/skel` toolkit files.
12. Cleans per-user homes (Plank, markers, legacy panel launchers, panel-2 xfconf, `libinput-gestures` autostart copies).
13. Clears `/var/lib/oem-setup/state/`.
14. `step_cleanup` + final autoremove + summary.

## Walkthrough

The function is long and intentionally linear. **Stop services before
purging packages** and **restore config files before `update-grub` /
`update-initramfs`** are the critical ordering constraints.

## Notes

- `step_uninstall` is invoked directly from the menu (option **15**), not
  via `do_step` / `run_step`. It owns its own confirmation
  (`read … YES`) and never writes a `uninstall.done` marker.
- The `for svc in tlp touchegg keyd; do … done`
  loop uses `systemctl list-unit-files | grep "^${svc}.service"`
  rather than `systemctl is-enabled` because the latter exits non-zero
  for "static", "alias", and other normal states.
- After package purges, `step_cleanup` runs so `/tmp` is scrubbed before exit.

## Idempotency

Fully idempotent: `rm -f`, tolerant `apt purge`, graceful `restore_or_skip`,
re-runs complete any remaining cleanup.

## Uninstall counterpart

N/A — this module *is* the uninstall.
