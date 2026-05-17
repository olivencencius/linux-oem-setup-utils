# `modules/xubuntu_boot.sh`

## Purpose

**Machine-wide** boot polish for **Xubuntu LTS** resale images on Chromebooks:
faster boot, quieter visuals, and less **TTY1 getty** noise before LightDM.

What it does:

- **`ensure_apt_fresh`** then **Plymouth** — installs `plymouth` and Xubuntu logo/text
  theme packages when available; sets **`xubuntu-logo`** (or **`xubuntu-text`**) as
  default when listed by `plymouth-set-default-theme`.
- **`ModemManager.service`** — `disable --now` (skips WWAN probing when no modem).
- **`NetworkManager-wait-online.service`** — `mask --now` (does not block boot on
  network readiness).
- **`snapd.socket` / `snapd.service`** — `disable --now`. Confirm the image does
  not rely on Snap-only apps before using this.
- **`/etc/default/grub`** — appends when missing: `quiet splash loglevel=3`
  `vt.global_cursor_default=0` **`systemd.show_status=no`**
  **`rd.systemd.show_status=no`**, then **`update-grub`** only if something changed.
- **`vt.handoff=7`** — appended **only** when **`/etc/grub.d/10_linux`** does **not**
  already define **`vt_handoff`** (stock Ubuntu GRUB injects handoff via `$vt_handoff`).

**Not implemented:** masking **`systemd-udev-settle.service`** — measure with
`systemd-analyze blame` first; masking manually remains optional if justified.

## Function exported

`step_xubuntu_boot`

## Inputs

- **`backup_once`**, **`ensure_apt_fresh`** from [`setup.sh`](../setup.sh).
- Existing **`/etc/default/grub`** (merge-safe with CELES HPET flags added by
  [`hardware.sh`](hardware.md) — runs **after** `hardware_fixes` in the default
  pipeline so tokens accumulate on one line).

## Outputs

- Possibly installed Plymouth packages and theme selection.
- systemd linkage under `/etc/systemd/system/`.
- Possibly modified `/etc/default/grub` and regenerated GRUB config.

## Pipeline placement

Invoked from **`run_full_pipeline`** immediately **after `hardware_fixes`**. Also
available standalone as **menu option `2`** (re-apply without re-running the full
pipeline).

## Menu integration

```bash
2)  do_step xubuntu_boot
```

Uses **`run_step`** in the full pipeline and **`do_step`** from the menu, so
`/var/lib/oem-setup/state/xubuntu_boot.done` records completion.

## Uninstall counterpart

[`step_uninstall`](uninstall.md) **unmasks** `NetworkManager-wait-online`,
re-**enables** ModemManager and snapd best-effort, and strips toolkit GRUB tokens
(`quiet`, `splash`, `loglevel=3`, `vt.global_cursor_default=0`,
`systemd.show_status=no`, `rd.systemd.show_status=no`, `vt.handoff=7`) when
restoring from backup is not possible — see [`../uninstall.md`](../uninstall.md).

## Related docs

- [`../pipeline.md`](../pipeline.md) — `run_step xubuntu_boot` placement.
- [`../handover-qa.md`](../handover-qa.md) — boot QA after deployment.
