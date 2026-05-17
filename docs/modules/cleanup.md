# `modules/cleanup.sh`

## Purpose

Scrubs `/tmp` of every artefact previous partial runs may have left
behind, so subsequent install steps always start from a known-empty
slate.

## Function exported

`step_cleanup`

## Inputs

None.

## Outputs (filesystem changes)

Removes — `rm -rf` for directories, `rm -f` for files, both ignore
"missing" without complaint:

- `/tmp/chromebook-linux-audio`
- `/tmp/cros-keyboard-map`
- `/tmp/libinput-gestures` *(upstream clone leftovers in /tmp — rare defensively cleared)*
- `/tmp/ChromeOS-theme` *(legacy — old `themes.sh` git-cloned this; current revision doesn't, but the entry is kept defensively for upgrades)*
- `/tmp/Tela-icon-theme` *(legacy — same reason as `ChromeOS-theme`)*
- `/tmp/google-chrome-stable_current_amd64.deb`
- `/tmp/zoom_amd64.deb`
- `/tmp/touchegg.deb` *(historical filenames from older revisions — harmless `rm -f`)*
- `/var/cache/oem-setup/libinput-gestures-src` *(cloned before `libinput-gestures-setup install`)*

Older revisions sideloaded `touchegg` from apt/PPA/deb paths; gestures now use **`libinput-gestures`** and may still wipe stale `/tmp/*.deb` names listed above.

## Walkthrough

A single `rm -rf` and a single `rm -f`. That's the whole script.

## Notes

- Called at multiple points: from `run_full_pipeline` (as the second
  step), from menu options 3, 4, and 9 (each chains it before its
  main step), and from `step_uninstall` near the end.
- The `do_step` wrapper means every call writes a `cleanup.done`
  marker. After a re-run, `run_step cleanup` short-circuits. That's
  fine — none of the things this step removes need to be removed
  twice.
- Does **not** touch anything outside `/tmp`. Every path is hard-coded.

## Idempotency

Fully idempotent — `rm -rf` / `rm -f` succeed regardless of whether
the target exists. Safe to run any number of times.

## Uninstall counterpart

`step_uninstall` calls `step_cleanup` at the end (sub-step 15) to
scrub `/tmp` again before exit. There is no "undo cleanup" — the
files it removes are downloads/clones that the toolkit always
re-fetches when needed.
