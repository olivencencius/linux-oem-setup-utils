# Chromebook Linux OEM deployment

A modular, automated deployment toolkit that converts MrChromebox-flashed
x86 / Intel Chromebooks into market-ready **Xubuntu LTS**
machines with a ChromeOS-like layout. Built for resale velocity on 4 GB RAM
hardware: hardware fixes, sensible defaults, dock-pinned apps, and a
single-command bootstrap.

## What it does in one screen

- **Driver and quirk fixes** — audio, top-row keys, board-specific kernel
  parameters (CELES HPET, Tiger/AlderLake USB-C), all detected
  automatically.
- **ChromeOS-like UX** — Plank dock with pinned apps, Malta wallpaper, top
  panel layout, natural scrolling, multi-finger gestures (libinput-gestures +
  xfdashboard). GTK/icon themes follow **distro defaults** (no custom theme
  packages from this toolkit).
- **Performance defaults for 4 GB eMMC** — ZRAM memory compression and
  TLP power management.
- **Boot polish** — systemd + GRUB + Plymouth for faster, quieter boot and
  less TTY flicker; applied automatically in the full pipeline (menu **2**
  re-applies the same step if needed).
- **Apps and shortcuts** — Google Chrome (with self-updating Google apt
  repo), Zoom, VLC, three games, 13 Chrome web-app launchers
  (Netflix, Prime Video, Disney+, Max, YouTube, Spotify, Gmail, Google Docs,
  Sheets, Slides, Drive, Gemini, Chrome Remote Desktop). GIMP is available as
  an optional menu item.
- **Full undo** — a single menu option reverses every change the toolkit
  makes.

Multimedia codec packs are **not** installed by this repo — enable them in the
OS installer or image if you need them.

## Prerequisites

Before running the setup toolkit, ensure:

- **Wi-Fi connection**: Stable, **>50 Mbps** network required (3 upstream git
  clones for audio, keyboard, and gestures). If your Wi-Fi is unreliable, re-run
  the setup — completed steps are skipped automatically.
- **Patience for hardware fixes**: The initramfs rebuild (Tiger/AlderLake USB-C
  support) may take **2–5 minutes** and can appear to freeze the UI. This is
  expected — do not interrupt.
- **Chrome download time**: Expect **5–20+ minutes** for the ~100 MiB Chrome
  .deb on slow CDNs. A progress bar will appear on the terminal.
- **Reboot required**: Kernel, initramfs, audio, and keyboard changes only take
  effect after a reboot — plan accordingly.

## How to run it

On a Chromebook running **Xubuntu LTS** with a technician account (ideally the
standard **`oem`** account from the OEM install workflow):

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
   Boot optimisations run **automatically** as part of option **1** (after
   hardware fixes). **Menu option 2** only re-runs that step in isolation.
5. When the pipeline finishes, **reboot**.
6. Run the per-machine [handover QA checklist](docs/handover-qa.md).
7. Double-click **Prepare for shipping to end user** on the desktop (or run
   `sudo oem-prepare-shipping` in a terminal), complete the prompts, then shut
   down when ready.

The buyer creates their own user account on first boot.

### Log file vs terminal

`/var/log/oem-setup.log` is an **append-only,
best-effort** mirror of the script’s normal output (apt, toolkit status lines,
errors). **Upstream audio and keyboard installers** in *hardware fixes* attach to the
**real terminal** so interactive prompts work — that UI is **not** copied into the
log. **Trust what you see on screen** during those steps; use the log for grep and
post-mortems elsewhere in the run.

### Re-running and resuming

`setup.sh` writes a marker per completed step into
`/var/lib/oem-setup/state/`. If anything fails or you Ctrl-C, re-run
`sudo bash setup.sh` — finished steps are skipped automatically.

To start completely over:

```bash
sudo rm -rf /var/lib/oem-setup/state && sudo bash setup.sh
```

### Reverting a deployment

Run the script again and pick **option 16 — Undo all changes**. See
[`docs/uninstall.md`](docs/uninstall.md) for what gets reverted and the
best-effort caveats.

## How it is organised

```
linux-oem-setup-utils/
├── bootstrap.sh       one-liner installer (installs git, clones, runs setup)
├── setup.sh           entry point: helpers, menu, full pipeline orchestrator
├── modules/           one .sh file per pipeline step
├── assets/            files installed onto the deployed machine
│   ├── configs/       libinput-gestures, workspace overview, OEM handover .desktop
│   ├── icons/         13 web-app icons (SVG)
│   ├── scripts/       oem-first-run.sh, oem-add-workspace.sh, oem-prepare-shipping.sh
│   └── wallpapers/    malta.jpg
├── skel/              copied to /etc/skel; step_themes adds Desktop launcher
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
- [`docs/uninstall.md`](docs/uninstall.md) — what option 15 reverts,
  and the best-effort caveats.
- [`docs/handover-qa.md`](docs/handover-qa.md) — the per-machine QA
  checklist to run before shipping.
