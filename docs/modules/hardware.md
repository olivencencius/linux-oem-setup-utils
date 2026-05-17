# `modules/hardware.sh`

## Purpose

The most board-specific module. Applies three families of fix that
together turn a generic **Xubuntu** install on a Chromebook into one
where the speakers, microphone, top-row keys, and (on
TigerLake/AlderLake) USB-C ports all work.

## Function exported

`step_hardware_fixes`

## Inputs

- Live network connectivity (to clone two GitHub repos and run their
  installers).
- A controlling TTY — the two upstream installers use **`oem_run_interactive`**
  (stdin/stdout/stderr on the real terminal). That session is **not** duplicated
  into `/var/log/oem-setup.log` (only START/END markers are); watch the screen.
- DMI / `/sys/class/dmi/id/product_name` for board detection.
- `lscpu` output for CPU detection.

## Outputs

- Whatever `WeirdTreeThing/chromebook-linux-audio` installs: ALSA UCM
  files under `/usr/share/alsa/`, udev rules under
  `/etc/udev/rules.d/99-cros-*`, PipeWire/Wireplumber overrides as
  needed by the detected board.
- Whatever `WeirdTreeThing/cros-keyboard-map` installs:
  `keyd` config under `/etc/keyd/`, the `keyd.service` enabled.
- For CELES (Samsung) boards: appends `clocksource=hpet hpet=force` to
  `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub`, runs
  `update-grub`.
- For TigerLake/AlderLake CPUs: appends `cros-ec-typec` and
  `intel-pmc-mux` to `/etc/initramfs-tools/modules`, runs
  `update-initramfs -u -k all`.

Two `backup_once` snapshots may be taken into `/var/lib/oem-setup/
backups/`:

- `grub` (from `/etc/default/grub`).
- `modules` (from `/etc/initramfs-tools/modules`).

## Walkthrough

### 1. Audio — `chromebook-linux-audio`

```bash
cd /tmp
rm -rf /tmp/chromebook-linux-audio
git clone --depth 1 https://github.com/WeirdTreeThing/chromebook-linux-audio.git
( cd /tmp/chromebook-linux-audio && oem_run_interactive ./setup-audio )
```

`oem_run_interactive` runs the installer with **stdin, stdout, and stderr on
the real TTY** (fd 3 in `setup.sh`). That matters when `setup.sh` was started
with `curl … | sudo bash`: the script’s stdin is still the curl pipe, but the
installer’s prompts must attach to the physical terminal.

### 2. Keyboard — `cros-keyboard-map`

Same shape as audio: clone under `/tmp`, then
`oem_run_interactive ./install.sh` inside the repo directory.

### 3. CELES (Samsung) — HPET clock source fix

```bash
local board=""
[ -r /sys/class/dmi/id/product_name ] && board=$(cat /sys/class/dmi/id/product_name)
if echo "$board" | grep -qi "celes" || dmesg | grep -qi "celes"; then
    if ! grep -q "clocksource=hpet" /etc/default/grub; then
        backup_once /etc/default/grub
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="clocksource=hpet hpet=force /' \
            /etc/default/grub
        update-grub
    fi
fi
```

DMI is the authoritative source for the board name. `dmesg` is the
fallback because on very rare boots the kernel ring-buffer has been
truncated by other early messages before we get a chance to read it.

The sed appends inside the existing quoted CMDLINE so no other kernel
parameters are clobbered. The `grep -q "clocksource=hpet"` guard
prevents a re-run from prepending a duplicate.

### 4. TigerLake / AlderLake — Type-C module fix

```bash
if lscpu | grep -qiE "tiger|alder"; then
    if ! grep -qx 'cros-ec-typec' /etc/initramfs-tools/modules; then
        backup_once /etc/initramfs-tools/modules
        echo "cros-ec-typec"  >> /etc/initramfs-tools/modules
        changed=1
    fi
    if ! grep -qx 'intel-pmc-mux' /etc/initramfs-tools/modules; then
        backup_once /etc/initramfs-tools/modules
        echo "intel-pmc-mux" >> /etc/initramfs-tools/modules
        changed=1
    fi
    [ "$changed" = "1" ] && update-initramfs -u -k all
fi
```

Forcing these two modules into the initramfs makes the kernel detect
the Chromebook's embedded Type-C controller early enough in boot for
the USB-C ports to come up. Without this, the ports work after a long
delay or not at all on 11th-gen-and-newer Chromebooks.

`update-initramfs -u -k all` is expensive (~30 seconds) — guarded
behind the `changed=1` check so a re-run doesn't pay the cost again.

## Notes

- **You must watch the screen during this step.** Both upstream
  installers can ask "which top-row layout?" and similar
  hardware-specific questions. Wrong answers here are the single
  most common cause of a deployment where the volume keys don't work.
- The audio installer occasionally also asks about reboot — answer
  "no" if asked, the toolkit's final reboot reminder covers it.
- `grep -qx` (exact-match) is used for the initramfs module check,
  because a partial match would let an existing `cros-ec-typec-foo`
  line silently fool the guard.
- Both kernel-mutation paths gate `update-grub` / `update-initramfs`
  behind the "did I actually change something?" check. This keeps a
  re-run from re-baking the initramfs every time.

## Idempotency

Fully idempotent thanks to:

- `rm -rf /tmp/...` before each clone.
- `grep` guards before each `sed` / `echo >>`.
- `backup_once` only snapshots the *first* mutation.

A second run on an already-fixed CELES board will detect the
parameter is present and skip the sed.

## Uninstall counterpart

`step_uninstall` (sub-step 5 and 6):

- **Audio**: best-effort `rm` of `cros-*` ALSA UCM files,
  `sof-*chrome*` configs, related udev rules and systemd units. A
  permanent `UNINSTALL_NOTES` entry warns that
  `chromebook-linux-audio` has no upstream uninstaller.
- **GRUB**: `restore_or_skip /etc/default/grub`. If no backup,
  sed-remove `clocksource=hpet hpet=force`. Then `update-grub`.
- **initramfs modules**: `restore_or_skip /etc/initramfs-tools/modules`.
  If no backup, sed-remove `cros-ec-typec` and `intel-pmc-mux`. Then
  `update-initramfs -u -k all`.
- **Keyboard map / keyd**: `apt purge keyd` (sub-step 2).
