# Uninstall — what `Undo all changes` reverts

Menu option **16** runs `step_uninstall`, the best-effort reversal of
every change this toolkit makes. This page explains exactly what it
does, in order, and where the inevitable "best-effort" caveats are.

For the per-module accounting see each module page; this is the
cross-cutting summary.

---

## How it's invoked

Menu option `16` calls `step_uninstall` directly (not via `do_step`).
The function asks for a `YES` (uppercase) confirmation read from
`/dev/tty`. Anything else aborts.

Unlike every other menu option, `step_uninstall` is **never** wrapped in
`do_step` / `run_step`. It owns its own confirmation and cleanup
sequencing, and we want it to always run when picked, regardless of any
`/var/lib/oem-setup/state/uninstall.done` marker (which is also why
none ever gets written).

---

## Helpers used

### `BACKUP_DIR` and `restore_or_skip`

```bash
BACKUP_DIR="/var/lib/oem-setup/backups"

restore_or_skip() {
    local target="$1"
    local backup="$BACKUP_DIR/$(basename "$target")"
    if [ -e "$backup" ]; then
        cp -a "$backup" "$target"
        return 0
    fi
    return 1
}
```

Whenever `step_uninstall` reverts a file:

- if `backup_once` snapshotted it during install, restore the snapshot
  byte-for-byte;
- otherwise fall back to a `sed` that removes only the lines the
  toolkit added.

That makes the uninstall safe to run on machines where the toolkit was
applied incompletely (some snapshots may be missing) and on machines
where the user later edited a file by hand (the sed fallback leaves
their edits alone).

### `note` and `UNINSTALL_NOTES`

```bash
UNINSTALL_NOTES=()
note() { UNINSTALL_NOTES+=("$1"); }
```

Anything the uninstall cannot fully reverse is appended to
`UNINSTALL_NOTES` and printed in the closing banner so the technician
knows what to look at manually.

---

## The 15 sub-steps

The function reads top-to-bottom in the same order. Numbering here
matches the inline section comments.

| # | Phase | Action |
|---|---|---|
| 1 | Stop services & user helpers | `systemctl disable --now` for `tlp`, `touchegg` (legacy), `keyd`. `pkill` `libinput-gestures` (all sessions). For `$SUDO_USER`: `pkill` `imwheel` / `libinput-gestures` / `plank` / `xfdashboard`. |
| 2 | `apt purge` everything the toolkit installs | Chrome, Zoom, `oem-config` + `oem-config-gtk`, VLC, TLP, ZRAM tools, `imwheel` (legacy), `plank`, **`touchegg` (legacy apt package**, if installed), **xfdashboard**, **rofi**, wmctrl, xdotool, keyd, language packs (`-pl`, `-gnome-pl`, `-en`, `-gnome-en`), `supertuxkart`, `aisleriot`, `quadrapassel`. If `step_gimp` was run (optional menu option 14), GIMP is also purged. **`libinput-gestures`** is removed via **`libinput-gestures-setup uninstall`**, not `apt purge`. Then `apt-get autoremove --purge` + `apt-get autoclean`. |
| 2b | Google apt repo | Remove `/etc/apt/sources.list.d/google-chrome.list`, `…/google.list`, `/usr/share/keyrings/google-chrome.gpg`, `/etc/apt/trusted.gpg.d/google-chrome.gpg`. `apt-get update` once to drop the entries from the cache. |
| 3 | *(reserved)* | Formerly Flathub remote removal; the toolkit no longer registers flatpak remotes. |
| 4 | Audio quirks | Best-effort `rm` of `/usr/share/alsa/ucm2/codecs/cros-*`, `cros-*` UCM trees, `sof-*chrome*` config, related udev rules and systemd units. Adds a note that `chromebook-linux-audio` has no upstream uninstaller — a clean OS install is the only fully-deterministic reset. |
| 5 | Hardware-fix + boot optimisations | `restore_or_skip /etc/default/grub` or sed-remove `clocksource=hpet hpet=force` **and** toolkit boot tokens (`quiet`, `splash`, `loglevel=3`, `vt.global_cursor_default=0`, `systemd.show_status=no`, `rd.systemd.show_status=no`, `vt.handoff=7`). **`update-grub`**. **Unmask + enable** `NetworkManager-wait-online`; **enable + start** `ModemManager`; **enable** `snapd.socket` / `snapd.service`. `restore_or_skip /etc/initramfs-tools/modules` or sed-remove Type-C module lines. **`update-initramfs -u -k all`**. |
| 6 | Touchpad/gestures config | `libinput-gestures-setup uninstall` when installed. Remove `/etc/xdg/autostart/libinput-gestures.desktop`, `/etc/libinput-gestures.conf`, upstream doc dir, clone dir under `/var/cache/oem-setup/`. `rm /etc/X11/xorg.conf.d/40-chromebook-touchpad.conf`, `restore_or_skip /etc/adduser.conf` (undo `EXTRA_GROUPS`/`input`). Scrub **`/etc/touchegg/`** (legacy). |
| 7 | Wallpaper / first-run / OEM handover launcher | `rm -rf /usr/share/backgrounds/oem-setup`. `rm /usr/local/bin/oem-first-run.sh`, `/usr/local/bin/oem-prepare-shipping`, `/usr/local/bin/oem-add-workspace.sh`. `rm` `/usr/share/applications/oem-prepare-shipping.desktop`, `oem-workspace-overview.desktop`. Also cleans legacy artefacts from earlier revisions: `rm /etc/dconf/db/local.d/00-plank`, `dconf update`. |
| 8 | Web-app shortcuts | `rm` thirteen `.desktop` entries (web apps) and matching icons. Refresh GTK icon cache. |
| 9 | Terminal | `restore_or_skip /etc/inputrc` or sed-remove the bracketed-paste line. Same on `/etc/skel/.inputrc`; remove the skel file if empty. |
| 10 | Regional | `restore_or_skip /etc/default/keyboard` or sed `XKBLAYOUT="us"`. `setupcon`. `localectl set-locale LANG=en_US.UTF-8`. `timedatectl set-timezone UTC`. |
| 11 | `/etc/skel` cleanup | `rm` current autostart entries (`oem-first-run`, `libinput-gestures` if present), `Desktop/oem-prepare-shipping.desktop`, legacy `xsettings.xml` if present. Defensive `rm -f` of legacy `touchegg-client.desktop` (migrated away from Touchegg). Also `rm -f` legacy artefacts (`.imwheelrc`, `imwheel.desktop`, `plank.desktop`, `plank/` tree, `gtk-4.0` symlinks) — no-ops on current revision. `rmdir` empty parents. |
| 12 | Per-user cleanup | For every uid ≥ 1000, plus `$SUDO_USER` (deduped): `rm` `.oem-first-run-done`, autostart entries, `Desktop/oem-prepare-shipping.desktop`, `launcher-NNN` dirs with NNN ≥ 100 under `~/.config/xfce4/panel/`, and legacy artefacts (`.imwheelrc`, `plank/`, `gtk-4.0` symlinks). xfconf `/panels/panel-2` subtree removed via `xfconf-query -r -R`. |
| 13 | Clear state markers | `rm -rf /var/lib/oem-setup/state` so a future setup.sh thinks the toolkit was never applied. Also `rm -f /var/lib/oem-setup/diagnostics-report.txt`. |
| 14 | `/tmp` residue + final autoremove | Call `step_cleanup`. `apt-get autoremove --purge`. |
| 15 | Closing summary | Print every entry in `UNINSTALL_NOTES`. Remind that backups remain at `BACKUP_DIR`. Recommend a reboot. |

---

## What is intentionally **not** removed

- **`/var/lib/oem-setup/backups/`** — the backups themselves stay
  on disk. They are small, they document what the original system
  looked like, and they let a future technician run uninstall again
  even if a partial re-install has happened in between.
- **The local repo checkout at `/var/cache/oem-setup-repo`** —
  removing it would break a re-run from the bootstrap. The buyer can
  remove it manually if they want.
- **User accounts** — `step_uninstall` removes toolkit *artefacts*
  from every user's home but leaves the accounts themselves intact.
- **Supplemental group `input`** on user accounts — `step_uninstall` does not
  attempt to remove people from this group; it is usually harmless. To strip
  it manually: `sudo deluser USER input` (repeat per account).

---

## Best-effort caveats

`UNINSTALL_NOTES` always contains:

> *chromebook-linux-audio has no upstream uninstaller — board-specific
> PipeWire/ALSA quirks may still be present. A fresh OS install is the
> only fully-clean reset.*

Other classes of un-revertable change documented elsewhere in the
toolkit:

- Kernel command-line parameters added by other tools (not via
  `/etc/default/grub`) are not touched.
- User accounts created *after* the install are not deleted; only the
  toolkit artefacts inside their homes are removed.

---

## Confirming an uninstall worked

```bash
# 1. Packages purged?
dpkg -l | grep -E 'google-chrome|zoom|plank|touchegg|tlp|zram-tools|imwheel'   # should be empty

# 2. Google apt repo gone?
ls /etc/apt/sources.list.d/google-chrome.list 2>/dev/null                       # should not exist

# 3. Kernel parameters gone?
grep CMDLINE /etc/default/grub                                                 # no clocksource=hpet; no toolkit boot tokens (quiet, splash, loglevel=3, vt.global_cursor_default=0, systemd.show_status=no, rd.systemd.show_status=no, vt.handoff=7) if sed fallback ran
grep -E 'cros-ec-typec|intel-pmc-mux' /etc/initramfs-tools/modules             # no matches

# 4. State cleared?
ls /var/lib/oem-setup/state/                                                   # should not exist
```

A reboot is recommended afterwards so the regenerated `grub.cfg`,
initramfs, and keyboard layout all take effect.
