# `modules/uninstall.sh`

## Purpose

Best-effort reversal of every change this toolkit makes. Returns the
machine as close as possible to a freshly-OEM-installed Linux Mint
XFCE state.

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
  - `user` (dconf profile)
- `$SUDO_USER` (optional) — used to kill the user's helpers
  (touchegg client, xfdashboard, plus legacy imwheel/plank from old
  installs) and to dedupe the per-user cleanup loop.
- `/dev/tty` — the `YES` confirmation prompt reads from it.

## Outputs

Reverts every system-level change the toolkit makes. A complete
sub-step-by-sub-step listing is in [`../uninstall.md`](../uninstall.md).

The headline buckets:

1. Stops services (`tlp`, `touchegg`, `keyd`, `oem-powerwash-finalize`)
   and user-session processes (`touchegg --client`, `xfdashboard`,
   plus legacy `imwheel` / `plank` from old installs).
2. `apt purge` 20+ packages, including `papirus-icon-theme` and the
   legacy `plank` / `imwheel` (in case an older revision installed
   them); then `apt-get autoremove --purge`, autoclean.
3. Removes the Google Chrome apt repository file and signing key.
4. Removes the Flathub remote.
5. (No theme reverse-install.) `Mint-Y-Aqua` is shipped by Mint and
   stays put; `papirus-icon-theme` is purged via apt in sub-step 2.
6. Best-effort cleans `chromebook-linux-audio` quirks (no upstream
   uninstaller — adds a note).
7. Reverts `/etc/default/grub`, `/etc/initramfs-tools/modules`
   (regenerates grub.cfg and initramfs after).
8. Removes touchpad and gestures system config.
9. Removes wallpaper, `/usr/local/bin/oem-first-run.sh`, and legacy
   Plank dconf override / dconf profile additions.
10. Removes the Powerwash tool (scripts, unit, polkit policy, menu,
    icon, flag).
11. Removes 11 web-app `.desktop` entries and their icons.
12. Reverts `/etc/inputrc` and `/etc/skel/.inputrc`.
13. Reverts `/etc/default/keyboard`, locale to `en_US.UTF-8`,
    timezone to `UTC`.
14. Cleans `/etc/skel` of toolkit artefacts.
15. Cleans `~/` of toolkit artefacts for every uid≥1000 (deduped),
    including `~/.config/xfce4/panel/launcher-NNN/` (NNN ≥ 100) and
    the panel-2 xfconf subtree.
16. Clears `/var/lib/oem-setup/state/` so a future setup.sh starts
    fresh.
17. `step_cleanup` + final `apt autoremove`.
18. Prints `UNINSTALL_NOTES` summary.

## Walkthrough

The function is long (~330 lines) and intentionally linear. The
ordering matters in two places:

1. **Stop services before purging their packages** — otherwise
   `apt purge touchegg` would refuse because the daemon is running, or
   `systemctl` would fail because the unit files have been removed.
2. **Restore system files before regenerating derived files** —
   `/etc/default/grub` is restored before `update-grub`;
   `/etc/initramfs-tools/modules` before `update-initramfs`.

The rest is independent and could be reordered without functional
change.

## Notes

- `step_uninstall` is invoked directly from the menu (option 16), not
  via `do_step` / `run_step`. It owns its own confirmation
  (`read … YES`) and never writes a `uninstall.done` marker. A re-run
  is always allowed.
- The `for svc in tlp touchegg keyd oem-powerwash-finalize; do … done`
  loop uses `systemctl list-unit-files | grep "^${svc}.service"`
  rather than `systemctl is-enabled` because the latter exits non-zero
  for "static", "alias", and other normal states.
- The per-user cleanup loop (sub-step 13) uses an associative array
  `SEEN` to dedupe between `/etc/passwd` (uid≥1000) and `$SUDO_USER`.
  Necessary because the technician's `$SUDO_USER` is usually already
  in `/etc/passwd` with uid 1000, but on some setups (LDAP, etc.)
  it isn't.
- After all the package purges, `step_cleanup` is called at the end
  (sub-step 15) so `/tmp` is also scrubbed before exit.

## Idempotency

Fully idempotent:

- Every `rm` is `-f` (no error on missing).
- Every `apt purge` is `|| true` or tolerates "not installed".
- `restore_or_skip` returns gracefully when no backup exists.
- `systemctl disable` of a missing or already-disabled unit is a
  no-op.
- Re-running on a partially-uninstalled machine completes the rest
  of the cleanup.

## Uninstall counterpart

n/a — this *is* the uninstall counterpart. There is no "re-install"
shortcut; running `setup.sh` again is the way to redeploy after an
uninstall.
