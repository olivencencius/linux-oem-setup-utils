# Architecture

This page documents the *run model* that `setup.sh` and every module sit on
top of: state markers, logging, error handling, the helpers exported to
modules, and how a resume works.

If you only want the order of steps, see [`pipeline.md`](./pipeline.md).
If you want what one module does, see [`modules/`](./modules/).

---

## File layout in one glance

```
linux-oem-setup-utils/
├── bootstrap.sh                ← one-liner: installs git, clones the repo, exec setup.sh
├── setup.sh                    ← entry point: helpers, menu, full pipeline orchestrator
├── modules/                    ← one .sh per pipeline step, each sourced (not executed)
│   ├── cleanup.sh
│   ├── updates.sh
│   ├── flathub.sh
│   ├── hardware.sh
│   ├── chrome.sh
│   ├── zoom.sh
│   ├── apps.sh
│   ├── webapps.sh
│   ├── themes.sh
│   ├── touchpad.sh
│   ├── gestures.sh
│   ├── terminal.sh
│   ├── regional.sh
│   ├── powerwash.sh
│   ├── diagnostics.sh
│   └── uninstall.sh
├── assets/                     ← anything the modules install onto the system
│   ├── configs/
│   ├── icons/
│   ├── scripts/
│   └── wallpapers/
├── skel/                       ← copied verbatim to /etc/skel by step_themes
└── docs/                       ← you are here
```

A complete map of every file under `assets/` and `skel/` (with install path
and owning module) lives in [`assets.md`](./assets.md).

---

## Two entry points

### `bootstrap.sh` — for a fresh OEM install

A buyer's machine just out of the Mint OEM installer doesn't have `git`. The
bootstrap exists to make the very first command be a single `curl | sudo bash`:

1. Refuses to run as non-root (`EUID != 0`).
2. Installs `git` via `apt-get install -y git` if missing.
3. Clones (or fast-forward pulls) the repo into `/var/cache/oem-setup-repo`.
   If the pull fails for any reason (dirty tree, diverged branch), wipes
   the cache and re-clones — the OEM workflow doesn't want stale code.
4. `exec`s `setup.sh` from that cache so the process becomes `setup.sh`.

### `setup.sh` — the engine

`setup.sh` is intentionally a self-contained framework that sources the
modules. Modules never `source` each other and never reach into each
other's internals — anything cross-cutting is exported by `setup.sh`.

The boot sequence inside `setup.sh`:

1. `set -Eeuo pipefail` so any unhandled error halts the script with a clear
   line number (see *Error handling* below).
2. Refuse to run if `EUID != 0`.
3. Resolve `REPO_DIR` to the absolute path of the script's own directory.
   Modules read assets via `$REPO_DIR/assets/...`, so a `curl | bash`
   invocation, a `cd` into the wrong place, or symlinks all work the same.
4. Create `LOG_FILE` (`/var/log/oem-setup.log`), `STATE_DIR`
   (`/var/lib/oem-setup/state`), and the backups directory
   (`/var/lib/oem-setup/backups`).
5. `exec > >(tee -a "$LOG_FILE") 2>&1` — tee everything (stdout + stderr)
   into the log file as well as the terminal, *before* sourcing modules,
   so their output is also captured.
6. Define the helpers `backup_once`, `ensure_apt_fresh`, `mark_done`,
   `is_done`, `do_step`, `run_step`; export the ones modules may call.
7. Install the `ERR` and `INT`/`TERM` traps.
8. `source` every `modules/*.sh`.
9. Show the menu loop and dispatch.

---

## State, idempotency, and resume

The toolkit is designed to be re-run safely after a crash, a Ctrl-C, a power
cut, or just to redo one step. The mechanism is intentionally simple: a
flat directory of empty marker files.

```
/var/lib/oem-setup/
├── state/
│   ├── cleanup.done
│   ├── updates.done
│   ├── chrome.done
│   ├── …                     ← one per successfully-completed step
│   └── kb_layout             ← persisted choice from prompt_keyboard
└── backups/                  ← snapshots taken by backup_once before mutation
    ├── grub
    ├── initramfs-tools-modules
    ├── inputrc
    ├── keyboard
    └── user                  ← /etc/dconf/profile/user
```

### `do_step` vs `run_step`

```bash
do_step <name>   # ALWAYS runs. Records the step as done on success.
run_step <name>  # Skips if /var/lib/oem-setup/state/<name>.done exists,
                 # otherwise calls do_step.
```

- The **menu's individual options** (`2`–`15`) call `do_step` so a
  technician can re-apply one step on demand even after a full pipeline.
  Option **`16`** (Undo all changes) is the exception — it calls
  `step_uninstall` directly (see [`modules/uninstall.md`](./modules/uninstall.md)).
  Option **`17`** exits without invoking a step.
- The **full pipeline** (option `1`) calls `run_step` so a re-run after a
  failure resumes from the broken step.

Both versions set `CURRENT_STEP` before invocation, which the error trap
reads to print a meaningful message.

### Forcing a clean re-run

```bash
sudo rm -rf /var/lib/oem-setup/state && sudo bash setup.sh
```

### Saved keyboard choice

`prompt_keyboard` persists the user's answer to
`/var/lib/oem-setup/state/kb_layout`. A resumed pipeline reads that file
and doesn't re-prompt. Delete the file to be asked again — useful when the
machine is being prepared for a different region than the previous one.

---

## Logging

- **Log file**: `/var/log/oem-setup.log` (append-only across runs).
- **Mechanism**: `exec > >(tee -a "$LOG_FILE") 2>&1` early in `setup.sh`.
  This redirects the shell's own stdout/stderr into a `tee` subprocess
  which writes to both the terminal *and* the log file. Modules need no
  awareness of this — every `echo`, every `apt-get` line, every error is
  captured automatically.
- **Why one file across runs**: when a step fails mid-pipeline the
  technician will run `setup.sh` again. Keeping the log appended lets them
  grep the whole history. Rotate or truncate manually if needed.
- **The Powerwash subsystem has its own log**: `/var/log/oem-powerwash.log`
  is written by `oem-powerwash-finalize.sh` on the post-powerwash boot.
  This is intentional — that script runs from a systemd service before
  any display manager and is not part of a `setup.sh` invocation.

---

## Error handling

```bash
trap 'on_err $LINENO' ERR
trap on_int           INT TERM
```

`on_err` fires on any `ERR` (because `set -e` is active) and prints a
banner like:

```
=================================================================
[!] FAILED at step: chrome  (line 11, exit 100)
[!] Log: /var/log/oem-setup.log
[!] Fix the cause, then re-run 'sudo bash setup.sh' — completed
    steps will be skipped automatically.
=================================================================
```

It does **not** touch the state directory. The failed step's marker was
never written (because `mark_done` runs *after* the step function
returns), so the next `run_step` will retry only the broken step.

`on_int` handles Ctrl-C / SIGTERM with a similar banner and exit code 130.

The `CURRENT_STEP` variable is set by both `do_step` and `run_step` so the
banner can name which step was running.

### `set -Eeuo pipefail` notes

- `-E` — `ERR` traps are inherited by functions. Without this, a failure
  inside a module function would not trigger the trap.
- `-e` — exit on any unhandled non-zero. Modules use `|| true` (zoom
  download, xfdashboard install, dconf update, theme reverse-install,
  every cleanup `rm`) when a single command's failure should not abort
  the run.
- `-u` — treat unset variables as errors. Modules guard with
  `${VAR:-default}` for optional inputs (`$SUDO_USER`, `$DISPLAY`,
  `$KB_LAYOUT`, `$OEM_APT_FRESH`).
- `-o pipefail` — a failure anywhere in a pipeline propagates.

---

## Exported helpers (modules call these)

### `backup_once <src>`

```bash
backup_once /etc/default/grub
```

Snapshots `<src>` into `/var/lib/oem-setup/backups/<basename>` **only on
the first call** — if the destination already exists, it is left alone.
This means `step_uninstall` can restore the file the toolkit *first*
saw, not whatever state it was in after a partial install.

Modules use it before every mutation of a system file that has a
counterpart in `step_uninstall`'s `restore_or_skip`:

- `/etc/default/grub`            (hardware HPET fix)
- `/etc/initramfs-tools/modules` (Type-C fix)
- `/etc/inputrc`                 (bracketed-paste fix)
- `/etc/default/keyboard`        (XKB layout)
- `/etc/dconf/profile/user`      (legacy — Plank dconf system db; only
  touched by `step_uninstall` to clean up older revisions)

If no backup exists at uninstall time, `restore_or_skip` falls back to a
sed-based removal of only the lines this toolkit added. Both paths are
tested.

### `ensure_apt_fresh`

```bash
ensure_apt_fresh
apt-get install -y something
```

Runs `apt-get update -qq` exactly **once per `setup.sh` invocation** by
setting `OEM_APT_FRESH=1` on the first call and short-circuiting on every
subsequent call.

This matters when a technician picks individual menu options:
- the full pipeline already calls `step_updates` which runs the real
  `apt-get update` and exports `OEM_APT_FRESH=1`, so later modules
  skip it;
- but an individual option (e.g. "5 Install Google Chrome") needs to
  refresh the cache itself because it might run on a freshly-rebooted
  machine. The first `ensure_apt_fresh` call in that session does the
  refresh, the rest no-op.

Modules call `ensure_apt_fresh` before *any* `apt-get install` they
issue.

### Step helpers

```bash
mark_done <name>     # touch /var/lib/oem-setup/state/<name>.done
is_done   <name>     # test for the marker

do_step  <name>      # sets CURRENT_STEP, echoes a banner, calls step_<name>,
                     # marks done on success, echoes "<== OK"
run_step <name>      # if is_done <name>: echo "skipped"; else do_step <name>
```

These are not exported because they are only used by `setup.sh` itself.

---

## REPO_DIR — why the path resolution matters

```bash
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_DIR
```

`${BASH_SOURCE[0]}` is the path to `setup.sh` itself, regardless of how
the script was invoked. `cd` + `pwd` collapses `.`, `..` and symlinks to
an absolute path. The result is exported so modules can do
`"$REPO_DIR/assets/icons/netflix.svg"` and not care about the technician's
current working directory.

This matters for two real-world entry paths:

- `bootstrap.sh` `exec`s `bash /var/cache/oem-setup-repo/setup.sh` —
  `REPO_DIR` resolves to `/var/cache/oem-setup-repo`.
- A direct `cd ~/dev/linux-oem-setup-utils && sudo bash setup.sh` —
  `REPO_DIR` resolves to that path instead.

In both cases the modules find their assets without any if/else.

---

## Menu

The menu is a simple `while true; do … done` `read` loop. Two design
points worth noting:

1. **`read … < /dev/tty`** — the read is bound to the terminal, not
   stdin, so the menu still works when the script was launched via
   `curl … | sudo bash` (stdin is the curl pipe at that point).
2. **`set -e` works under a function returning non-zero** — `case` arms
   like `do_step cleanup; do_step updates` chain via `;` not `&&` so the
   second one is unaffected by a non-zero return from a function that
   intentionally short-circuits.

After option 1 (full pipeline) the menu `break`s and prints the
*Operation End* banner and the reboot reminder. Every other option loops
back so the technician can run multiple steps in one session.

---

## Reboot reminder

Several steps only take full effect after the next boot — kernel
parameters via GRUB, initramfs module list, audio quirks, keyboard
layout, locale. `setup.sh` always prints a reminder banner after the
full pipeline returns, regardless of whether any of those steps actually
ran. It is intentionally noisy: the cost of an extra reboot is zero, the
cost of shipping a machine where the audio works only after a reboot the
buyer never performed is the entire deployment.
