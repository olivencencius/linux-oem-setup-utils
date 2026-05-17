# Chromebook Linux OEM deployment

A modular, automated deployment toolkit that converts MrChromebox-flashed
x86 / Intel Chromebooks into market-ready **Linux Mint XFCE** or **Xubuntu**
machines with a ChromeOS-like layout. Built for resale velocity on 4 GB RAM
hardware: hardware fixes, sensible defaults, dock-pinned apps, and a
single-command bootstrap.

## What it does in one screen

- **Driver and quirk fixes** — audio, top-row keys, board-specific kernel
  parameters (CELES HPET, Tiger/AlderLake USB-C), all detected
  automatically.
- **ChromeOS-like UX** — Plank dock with pinned apps, Malta wallpaper, top
  panel layout, natural scrolling, multi-finger gestures (touchegg +
  xfdashboard). GTK/icon themes follow **distro defaults** (no custom theme
  packages from this toolkit).
- **Performance defaults for 4 GB eMMC** — ZRAM memory compression and
  TLP power management.
- **Apps and shortcuts** — Google Chrome (with self-updating Google apt
  repo), Zoom, VLC, GIMP, three games, 11 Chrome web-app launchers
  (Netflix, Prime Video, Disney+, Max, YouTube, Spotify, Gmail, Docs,
  Drive, Gemini, Chrome Remote Desktop).
- **Full undo** — a single menu option reverses every change the toolkit
  makes.

Multimedia codec packs are **not** installed by this repo — enable them in the
OS installer or image if you need them.

## How to run it

On a Chromebook freshly OEM-installed with Linux Mint XFCE or Xubuntu:

1. Log into the temporary `oem` desktop and connect to Wi-Fi.
2. Open a terminal.
3. Run the single bootstrap command:

   ```bash
   curl -sL https://raw.githubusercontent.com/olivencencius/linux-oem-setup-utils/main/bootstrap.sh | sudo bash
   ```

4. Pick **option 1** (Run entire pipeline). Answer the keyboard-layout
   question, then watch the screen during *hardware fixes* — the
   upstream audio and keyboard installers may ask which top-row layout
   you want.
5. When the pipeline finishes, **reboot**.
6. Run the per-machine [handover QA checklist](docs/handover-qa.md).
7. Double-click the **Prepare for shipping to end user** icon on the
   desktop, enter the OEM password, then shut down.

The buyer creates their own user account on first boot.

### Re-running and resuming

`setup.sh` writes a marker per completed step into
`/var/lib/oem-setup/state/`. If anything fails or you Ctrl-C, re-run
`sudo bash setup.sh` — finished steps are skipped automatically.

To start completely over:

```bash
sudo rm -rf /var/lib/oem-setup/state && sudo bash setup.sh
```

### Reverting a deployment

Run the script again and pick **option 14 — Undo all changes**. See
[`docs/uninstall.md`](docs/uninstall.md) for what gets reverted and the
best-effort caveats.

## How it is organised

```
linux-oem-setup-utils/
├── bootstrap.sh       one-liner installer (installs git, clones, runs setup)
├── setup.sh           entry point: helpers, menu, full pipeline orchestrator
├── modules/           one .sh file per pipeline step
├── assets/            files installed onto the deployed machine
│   ├── configs/       touchegg, workspace overview .desktop
│   ├── icons/         11 web-app icons
│   ├── scripts/       oem-first-run.sh (per-user wallpaper + dock)
│   └── wallpapers/    malta.jpg
├── skel/              copied verbatim to /etc/skel (user defaults)
├── docs/              full technical documentation — start at docs/README.md
└── LICENSE
```

## More documentation

Everything beyond the quickstart lives in **[`docs/`](docs/)**:

- [`docs/architecture.md`](docs/architecture.md) — how `setup.sh`
  orchestrates everything (state, logging, traps, resume, helpers).
- [`docs/pipeline.md`](docs/pipeline.md) — the full pipeline as one
  ordered list, with a paragraph on why each step is where it is.
- [`docs/modules/`](docs/modules/) — one page per module: purpose,
  inputs, outputs, walkthrough, idempotency, uninstall counterpart.
- [`docs/assets.md`](docs/assets.md) — every file in `assets/` and
  `skel/` mapped to its install path and owning module.
- [`docs/uninstall.md`](docs/uninstall.md) — what option 14 reverts,
  and the best-effort caveats.
- [`docs/handover-qa.md`](docs/handover-qa.md) — the per-machine QA
  checklist to run before shipping.
