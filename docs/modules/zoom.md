# `modules/zoom.sh`

## Purpose

Installs the official Zoom desktop client from upstream's amd64 `.deb`.

## Function exported

`step_zoom`

## Inputs

- `ensure_apt_fresh` (helper from `setup.sh`).
- Live network connectivity (downloads from `zoom.us`).

## Outputs

- The `zoom` package installed (`/usr/bin/zoom` and its data).
- `/usr/share/applications/Zoom.desktop` — the file the Plank dock
  launcher (created at first login by `oem-first-run.sh`) references.
- Branded icon under `/usr/share/icons/hicolor/...` (shipped by the
  `.deb`).

## Walkthrough

```bash
local deb=/tmp/zoom_amd64.deb
rm -f "$deb"

wget -q --show-progress -O "$deb" https://zoom.us/client/latest/zoom_amd64.deb || true

if [ ! -s "$deb" ]; then
    rm -f "$deb"
    return 0
fi

ensure_apt_fresh
apt-get install -y "$deb"
rm -f "$deb"
```

Looks like `step_chrome` with one critical difference: **the empty-file
check returns 0, not 1**. Zoom is "nice to have", not "must ship". A
download failure prints a warning and the rest of the pipeline
continues.

The `|| true` on the `wget` line is the same idea — keeps `set -e`
from killing the whole pipeline on a flaky CDN.

## Notes

- `Zoom.desktop` (capital Z) is the exact filename shipped by the
  upstream `.deb`; the `DOCK_LAUNCHERS` entry in `oem-first-run.sh`
  references that case-sensitively.
- If Zoom's download fails, the Plank dock will be short by one icon
  (`oem-first-run.sh` checks `/usr/share/applications/Zoom.desktop`
  exists before adding the launcher and silently skips it otherwise).
  The technician sees a clear warning in the log so they can re-run
  option 6 once connectivity is restored.

## Idempotency

Fully idempotent for the same reason as `step_chrome`. A re-run will
fetch the latest `.deb` and let apt decide whether to upgrade or
no-op.

## Uninstall counterpart

`step_uninstall` runs `apt-get purge -y zoom` (sub-step 2). Zoom does
not register its own apt repository (it uses the Zoom auto-updater
inside the app instead), so no key/repo cleanup is needed.
