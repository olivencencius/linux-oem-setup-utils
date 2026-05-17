# Documentation

This directory holds the deep-dive documentation for `linux-oem-setup-utils`.
The top-level [`README.md`](../README.md) is intentionally slim — it tells you
*what* the toolkit is and *how* to run it. Everything else lives here.

## Where do I look?

| If you want to… | Read this |
|---|---|
| Understand how `setup.sh` orchestrates everything (state, logging, resume, traps, helpers) | [`architecture.md`](./architecture.md) |
| See the full pipeline as one ordered list with the reason each step is where it is | [`pipeline.md`](./pipeline.md) |
| Know what an individual module does, what it reads, what it writes | [`modules/`](./modules/) |
| Trace every file in `assets/` and `skel/` to its install path and the module that places it | [`assets.md`](./assets.md) |
| Audit exactly what `Undo all changes` reverts, and the best-effort caveats | [`uninstall.md`](./uninstall.md) |
| Run the per-machine QA checklist before handover | [`handover-qa.md`](./handover-qa.md) |

## Per-module pages

One file per script in `modules/`, all follow the same template
(*Purpose / Inputs / Outputs / Walkthrough / Notes / Idempotency / Uninstall counterpart*).

- [`modules/cleanup.md`](./modules/cleanup.md)
- [`modules/updates.md`](./modules/updates.md)
- [`modules/hardware.md`](./modules/hardware.md)
- [`modules/chrome.md`](./modules/chrome.md)
- [`modules/zoom.md`](./modules/zoom.md)
- [`modules/apps.md`](./modules/apps.md)
- [`modules/webapps.md`](./modules/webapps.md)
- [`modules/themes.md`](./modules/themes.md)
- [`modules/touchpad.md`](./modules/touchpad.md)
- [`modules/gestures.md`](./modules/gestures.md)
- [`modules/terminal.md`](./modules/terminal.md)
- [`modules/regional.md`](./modules/regional.md)
- [`modules/diagnostics.md`](./modules/diagnostics.md)
- [`modules/uninstall.md`](./modules/uninstall.md)

## Conventions used in these docs

- **Module** — a file under `modules/`. Each module defines one `step_<name>`
  function and is sourced (not executed) by `setup.sh`.
- **Step** — one invocation of a `step_<name>` function via `do_step` (always
  runs) or `run_step` (skipped if already marked done).
- **Marker** — an empty file under `/var/lib/oem-setup/state/<name>.done`
  that records a step finished successfully.
- **`backup_once`** / **`ensure_apt_fresh`** — helpers exported by
  `setup.sh`; modules call them but never define them. See
  [`architecture.md`](./architecture.md).
- **`$REPO_DIR`** — the absolute path to the cloned repository, exported by
  `setup.sh`. Modules use it to reach `assets/`, `skel/`, etc. regardless of
  where the script was invoked from.
- **Live oem session** — the temporary `oem` user account created by Mint's
  OEM installer. Some modules apply changes to this session immediately so
  the technician can QA before handover; the same changes are also staged
  into `/etc/skel` so every future user inherits them.
