# `modules/diagnostics.sh`

## Purpose

Runs **fully automatic** inventory and best-effort functional probes at the
end of the deployment pipeline (and on demand from the menu). Prints a
structured report to the terminal (colour when stdout is a TTY) and writes a
plain-text copy to
`/var/lib/oem-setup/diagnostics-report.txt`. Includes a short **manual-only**
block pointing technicians at [`handover-qa.md`](../handover-qa.md) for checks
that cannot be scripted.

## Function exported

`step_diagnostics`

## Inputs

- Root privileges (`setup.sh` already requires root).
- Optional **`SUDO_USER`** — when set (typical `sudo bash setup.sh`), Pulse /
  PipeWire queries use `sudo -u "$SUDO_USER"` with `XDG_RUNTIME_DIR` so
  `pactl` can reach the logged-in session; same pattern as [`touchpad.md`](./touchpad.md)
  for `xinput` / `xrandr`.
- Sysfs, `/proc`, `lscpu`, `lsblk`, `lsusb`, `lspci`, `pactl`, `nmcli`,
  `systemctl`, `lsmod`, `dmidecode` (optional), `lsinitramfs` (optional).

## Outputs

- **Terminal**: full report (stderr is unchanged; normal messages still go to
  `/var/log/oem-setup.log` via `setup.sh`'s `tee`).
- **`/var/lib/oem-setup/diagnostics-report.txt`** — plain lines only (no ANSI).

No packages installed, no config files modified.

## Walkthrough

### 1. Inventory sections

Best-effort enumeration of vendor/product/BIOS, CPU, RAM (including `dmidecode`
when available), disks, battery health from `BAT*` sysfs, GPU (`lspci`), USB
device count, Type-C port count from `/sys/class/typec/port*/`, audio sinks /
sources, headphone jack hints from codec dumps + `pactl`, V4L2 nodes, network
devices (`nmcli`), Bluetooth, `xinput` summary, lid / IIO sensors.

### 2. Automated `[PASS]` / `[WARN]` / `[FAIL]` checks

Examples: default PipeWire/Pulse sink/source not null and not muted; `keyd`
active with `/etc/keyd/*.conf`; touchpad snippet + `xinput` detection; webcam
nodes + kernel module heuristic; CELES HPET cmdline; Tiger/AlderLake USB-C
modules + initramfs listing; TLP enabled; ZRAM present; `touchegg` active; all
13 web-app `.desktop` files; OEM wallpaper; Powerwash `.desktop` + polkit
action; suspend capability; writable backlight.

Each `[FAIL]` includes a one-line hint naming the relevant **`setup.sh`** menu
option to re-run.

### 3. Manual-only block

Printed checklist items (speakers, headphone jack behaviour, per-key
verification, per-port USB sticks, live camera preview, lid suspend, Wi-Fi
after suspend) — **not** executed.

### 4. Summary line

Counts PASS / WARN / FAIL / MANUAL and repeats the report file path.

## Notes

- **`step_diagnostics` always returns 0** — failures are reported inline, not
  raised, so the pipeline never aborts on a failed probe under `set -e`.
- First pipeline run **before** a reboot may show false negatives for audio /
  USB-C / keyboard until hardware fixes have taken effect; [`pipeline.md`](../pipeline.md)
  and the reboot reminder still apply.

## Idempotency

Read-only with respect to system configuration. Safe to run repeatedly;
overwrites `diagnostics-report.txt` each time.

## Uninstall counterpart

[`step_uninstall`](./uninstall.md) removes `/var/lib/oem-setup/diagnostics-report.txt`
alongside clearing `/var/lib/oem-setup/state/` (see uninstall sub-step 14).
