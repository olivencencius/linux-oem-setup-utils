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
- `/tmp/ChromeOS-theme`
- `/tmp/Tela-icon-theme`
- `/tmp/google-chrome-stable_current_amd64.deb`
- `/tmp/zoom_amd64.deb`
- `/tmp/touchegg.deb`

The `touchegg.deb` entry is a historical artefact from when touchegg was
sideloaded from a GitHub release; the current `modules/gestures.sh`
installs it from apt and never produces this file. It's listed
anyway, harmlessly, because some old QA machines may still have one.

## Walkthrough

A single `rm -rf` and a single `rm -f`. That's the whole script.

## Notes

- Called at multiple points: from `run_full_pipeline` (as the second
  step), from menu options 2 and 4 and 9 (each chains it before its
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
