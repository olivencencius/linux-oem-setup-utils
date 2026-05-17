# `modules/regional.sh`

## Purpose

**`step_regional`** installs Polish and English GNOME/language packs plus
`locales`, ensures `pl_PL.UTF-8` and `en_US.UTF-8` are generated, and sets the
system default locale to **`LANG=pl_PL.UTF-8`** via **`localectl`**.

**Keyboard layout** and **timezone** are intentionally **not** changed here —
they match what was chosen during **Xubuntu / OEM installation**.

## Functions exported

- **`step_regional`** — invoked by **`run_step regional`** from the full
  pipeline (`setup.sh` menu option **1**), or by **`do_step regional`** from
  menu option **13** (`Polish language packs and system locale`).

## Inputs

- **`ensure_apt_fresh`** (from `setup.sh`).

## Outputs

Installed packages:

- `language-pack-pl`, `language-pack-gnome-pl`
- `language-pack-en`, `language-pack-gnome-en`
- `locales`

System files:

- `/etc/locale.gen` (via `locale-gen`) — `pl_PL.UTF-8` and `en_US.UTF-8`
  ensured compiled.
- `/etc/default/locale` (via `localectl`) — `LANG=pl_PL.UTF-8`.

## Walkthrough

1. **`apt-get install`** for the language packs and `locales`.
2. **`locale-gen pl_PL.UTF-8 en_US.UTF-8 || true`** — belt and braces so
   `language-pack-pl` having enabled entries in `/etc/locale.gen` definitely
   results in compiled locales before switching.
3. **`localectl set-locale LANG=pl_PL.UTF-8`**.

## Notes

Runs **late** in the pipeline so heavy language-pack installs do not delay
Chrome, gestures, themes, etc.

## Idempotency

- **`apt-get install`** is a no-op for already-installed packages.
- **`locale-gen`** for existing locales is cheap / effectively a no-op.
- **`localectl set-locale`** re-applying the same value is a no-op.

## Uninstall counterpart

**`step_uninstall`** (`modules/uninstall.sh`):

- Purges language packs (sub-step 2).
- Uninstall **sub-step** **10**: keyboard via **`restore_or_skip`** only when a
  legacy **`backup_once`** snapshot exists (else **`sed`** `XKBLAYOUT="us"` and
  **`setupcon`**), **`localectl set-locale LANG=en_US.UTF-8`**, and
  **`timedatectl set-timezone UTC`**.
- Sub-step **13** clears **`/var/lib/oem-setup/state/`** entirely
  (including a legacy **`kb_layout`** file from older releases, if present).
