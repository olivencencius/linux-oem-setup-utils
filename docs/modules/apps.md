# `modules/apps.sh`

## Purpose

Installs the default user-facing applications via apt: VLC media
player and three small games (`supertuxkart`, `aisleriot`,
`quadrapassel`).

## Function exported

`step_apps`

## Inputs

- `ensure_apt_fresh` (helper from `setup.sh`).

## Outputs

- `vlc` package and its `/usr/share/applications/vlc.desktop` (the
  file Plank references via `oem-first-run.sh`.
- `supertuxkart`, `aisleriot`, `quadrapassel` packages and their
  menu entries.

## Walkthrough

```bash
ensure_apt_fresh
apt-get install -y vlc supertuxkart aisleriot quadrapassel
```

Two lines. Deliberately boring.

## Notes

- **Why apt?** Keeps disk and RAM use low on 4 GB eMMC; no separate app runtime trees.
- Spotify is **not** in this module. It is delivered as a Chrome web
  app by `step_web_apps` — the native Linux client is 200+ MB and
  noticeably heavier than the PWA on 4 GB RAM.
- GIMP is installed by `step_updates`, not this module — see
  [`updates.md`](./updates.md) for the rationale.

## Idempotency

Fully idempotent — `apt-get install -y` is a no-op for already-installed
packages.

## Uninstall counterpart

`step_uninstall` purges (sub-step 2):

- `vlc`
- `supertuxkart`
- `aisleriot`
- `quadrapassel`

Followed by `apt-get autoremove --purge` to drop transitive deps.
