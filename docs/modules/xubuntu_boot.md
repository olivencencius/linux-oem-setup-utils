# `modules/xubuntu_boot.sh`

## Purpose

Optional **machine-wide** boot optimisations for **Xubuntu** and similar
Ubuntu-family resale images on Chromebooks. Intended for technicians who want
faster login and quieter boot visuals — **not** included in the default full
pipeline (menu option **1**).

What it does:

- **`ModemManager.service`** — `disable --now` (skips WWAN probing when no modem).
- **`NetworkManager-wait-online.service`** — `mask --now` (does not block boot on
  network readiness).
- **`snapd.socket` / `snapd.service`** — `disable --now`. Confirm the image does
  not rely on Snap-only apps before using this.
- **`/etc/default/grub`** — appends `quiet splash loglevel=3
  vt.global_cursor_default=0` to `GRUB_CMDLINE_LINUX_DEFAULT` when missing, then
  **`update-grub`** only if something changed.

**Not implemented:** masking **`systemd-udev-settle.service`** — measure with
`systemd-analyze blame` first; masking manually remains optional if justified.

## Function exported

`step_xubuntu_boot`

## Inputs

- **`backup_once`** from [`setup.sh`](../setup.sh).
- Existing **`/etc/default/grub`** (merge-safe with CELES HPET flags added by
  [`hardware.sh`](hardware.md) — run hardware fixes before or after; GRUB line is
  merged by append-only edits).

## Outputs

- systemd linkage under `/etc/systemd/system/`.
- Possibly modified `/etc/default/grub` and regenerated GRUB config.

## Pipeline placement

**None.** Invoked **only** from **menu option `2`**. Never called by
`run_full_pipeline`.

## Menu integration

```bash
2)  do_step xubuntu_boot
```

Uses **`do_step`**, so a completing run writes
`/var/lib/oem-setup/state/xubuntu_boot.done` — harmless because option **`1`**
never reads it.

## Uninstall counterpart

[`step_uninstall`](uninstall.md) **unmasks** `NetworkManager-wait-online`,
re-**enables** ModemManager and snapd best-effort, and strips toolkit GRUB tokens
when restoring from backup is not possible — see [`../uninstall.md`](../uninstall.md).

## Related docs

- [`../pipeline.md`](../pipeline.md) — documents that **`step_xubuntu_boot`** is
  excluded from the default pipeline.
- [`../handover-qa.md`](../handover-qa.md) — optional boot QA after menu option **2**.
