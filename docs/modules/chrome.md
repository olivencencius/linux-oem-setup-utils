# `modules/chrome.sh`

## Purpose

Installs Google Chrome stable (amd64) from the upstream `.deb`. The
package's postinst registers Google's apt repository
(`/etc/apt/sources.list.d/google-chrome.list`) and signing key, so
Chrome stays current via the system's normal `apt update` cycle.

## Function exported

`step_chrome`

## Inputs

- `ensure_apt_fresh` (helper from `setup.sh`).
- Live network connectivity (downloads from `dl.google.com`).

## Outputs

- `/usr/bin/google-chrome` and the rest of the package (`google-chrome-stable`).
- `/usr/share/applications/google-chrome.desktop` — the file the
  Plank `google-chrome.dockitem` references.
- `/etc/apt/sources.list.d/google-chrome.list` — registered by
  Chrome's postinst.
- `/usr/share/keyrings/google-chrome.gpg` (or
  `/etc/apt/trusted.gpg.d/google-chrome.gpg`, depending on Chrome
  version) — the apt signing key.

## Walkthrough

```bash
local deb=/tmp/google-chrome-stable_current_amd64.deb
rm -f "$deb"
wget -q --show-progress -O "$deb" \
    https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

if [ ! -s "$deb" ]; then
    rm -f "$deb"
    return 1
fi

ensure_apt_fresh
apt-get install -y "$deb"
rm -f "$deb"
```

Linear and conservative:

1. Remove any leftover `.deb` from a previous partial run (also done
   by `step_cleanup`, but cheap to repeat).
2. `wget -q --show-progress` keeps the run logs readable (no chatty
   HTTP headers) while still showing a percentage bar.
3. `[ ! -s ]` checks that the `.deb` is non-empty. `wget` can return
   `0` with a zero-byte file on certain CDN failures; this catches
   that.
4. Critical: **`return 1`** on an empty download. Chrome is **not**
   optional — every dockitem, every web-app shortcut, every QA step
   depends on it. Without Chrome the deployment is fundamentally
   broken; failing fast here is correct.
5. `ensure_apt_fresh` before `apt-get install` so the install doesn't
   fall over a stale cache on a fresh `apt-get install <local.deb>`
   run that needs to resolve dependencies.
6. Always `rm -f` the `.deb` after install to keep `/tmp` clean.

## Notes

- The `.deb` path embeds `_current_` in the filename. Google rewrites
  this to the latest stable version on every request, so no version
  pin is ever needed.
- `apt-get install -y "$deb"` (not `dpkg -i`) is used because apt
  knows how to resolve and install the dependencies declared by the
  `.deb` (libgbm1, libxkbcommon0, etc.) in one step.

## Idempotency

Fully idempotent. A re-run after a successful install:

1. Re-downloads the latest `.deb`.
2. `apt-get install -y` notices Chrome is already installed at that
   version or a newer one and reports "0 upgraded, 0 newly installed".

If Google has released a newer stable since the previous run, the
re-run will upgrade — which is desirable, not a problem.

## Uninstall counterpart

`step_uninstall` (sub-steps 2 and 2b):

- `apt-get purge -y google-chrome-stable`.
- `apt-get autoremove --purge` to drop Chrome's transitive deps.
- `rm -f` for `/etc/apt/sources.list.d/google-chrome.list`,
  `/etc/apt/sources.list.d/google.list`,
  `/etc/apt/trusted.gpg.d/google-chrome.gpg`,
  `/usr/share/keyrings/google-chrome.gpg`.
- `apt-get update` once afterwards to drop the Google entries from
  the cache.

The repo and key removal is **not optional**: `apt purge` of the
package does not touch them, and without this cleanup `apt update`
would keep talking to Google forever.
