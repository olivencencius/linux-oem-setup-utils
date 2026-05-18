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
   wget -qO- https://raw.githubusercontent.com/olivencencius/linux-oem-setup-utils/main/bootstrap.sh | sudo bash
   ```

4. Pick **option 1** (Run entire pipeline). Watch the terminal during
   *hardware fixes* — the upstream audio and keyboard installers may ask
   which **top-row** layout you want. **Keyboard layout and timezone** stay
   as set during **Xubuntu installation**; `step_regional` only adds Polish
   language packs and switches the **system locale** (`LANG`).
   Boot optimisations run **automatically** as part of option **1** (after
   hardware fixes). **Menu option 2** only re-runs that step in isolation.
5. When the pipeline finishes, **reboot** and run the per-machine [handover QA checklist](docs/handover-qa.md) where applicable.
6. When you are ready to hand over, run **`oem-prepare-shipping.sh` as root** (it is
   **not** installed by this toolkit). For example:

   ```bash
   wget -qO- https://raw.githubusercontent.com/olivencencius/linux-oem-setup-utils/main/assets/scripts/oem-prepare-shipping.sh | sudo bash
   ```

   Or from a clone: `sudo bash /path/to/linux-oem-setup-utils/assets/scripts/oem-prepare-shipping.sh`.
   Complete the prompts, then shut down when ready. Confirm a **buyer cold boot** (wizard, not a stuck login) before shipping — see [Handover QA](docs/handover-qa.md).

   The buyer’s **first cold boot** after you ship should show the **OEM / first-time setup wizard** (new account, language, etc.), not a bare LightDM-style login. If they only get a username and password prompt, see **[Handover QA — if the buyer only sees a normal login](docs/handover-qa.md#if-the-buyer-only-sees-a-normal-login)**.

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

**Extra user accounts** — **`oem-sync-all-user-homes.sh`** pushes **`oem-first-run`**
autostart, **`inputrc`**, and group **`input`** to every UID **1000–65533**. That only
works if the **machine already has** the same system-wide assets the pipeline installs
(wallpaper, Plank, **`oem-first-run.sh`**, Chrome, **13** web shortcuts, VLC + games,
workspace-overview launcher) — the script **preflights** those and warns (or aborts
with **`--strict`**). Typical order: run **menu 1** (or **5–9** as needed), then sync.

   ```bash
   wget -qO- https://raw.githubusercontent.com/olivencencius/linux-oem-setup-utils/main/assets/scripts/oem-sync-all-user-homes.sh | sudo bash -s --
   ```

   Full **oem-first-run** replay on next login (wallpaper, panel, dock — use after dock/wallpaper fixes):

   ```bash
   wget -qO- https://raw.githubusercontent.com/olivencencius/linux-oem-setup-utils/main/assets/scripts/oem-sync-all-user-homes.sh | sudo bash -s -- --reset
   ```

   Abort if anything required is missing (instead of warn-only):

   ```bash
   wget -qO- https://raw.githubusercontent.com/olivencencius/linux-oem-setup-utils/main/assets/scripts/oem-sync-all-user-homes.sh | sudo bash -s -- --strict --reset
   ```

   From a clone: `sudo bash assets/scripts/oem-sync-all-user-homes.sh` (same flags).

| System piece | Menu / step |
|--------------|-------------|
| Malta wallpaper, Plank, `/usr/local/bin/oem-first-run.sh`, `/etc/skel` autostart | **1** or **9** (`themes`) |
| Google Chrome | **5** |
| Zoom (optional; network install may skip) | **6** — if missing, Plank omits that pin only |
| VLC + SuperTuxKart + Aisleriot + Quadrapassel | **7** (`apps`) |
| 13 web-app `.desktop` + icons | **8** (`web_apps`) |
| libinput-gestures, **`input`** in `adduser.conf`, **`oem-workspace-overview.desktop`** | **9** or **11** (`gestures_and_workspaces`) |

**`step_themes`** (menu **9**) also syncs **`oem-first-run.desktop`** into homes that
lack **`~/.config/.oem-first-run-done`**. To force one user to re-run layout, remove
their **`~/.config/.oem-first-run-done`** (and optionally **`~/.config/plank`**) then
sync or **log in again**.

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
│   ├── configs/       libinput-gestures, workspace overview; optional OEM `.desktop` in repo only
│   ├── icons/         13 web-app icons (SVG)
│   ├── scripts/       oem-first-run.sh, oem-sync-all-user-homes.sh, oem-add-workspace.sh, oem-prepare-shipping.sh (ad-hoc / handover)
│   └── wallpapers/    malta.jpg
├── skel/              copied to /etc/skel (autostart); pipeline does not add Desktop handover launcher
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
- [`docs/uninstall.md`](docs/uninstall.md) — what option 16 reverts,
  and the best-effort caveats.
- [`docs/handover-qa.md`](docs/handover-qa.md) — the per-machine QA
  checklist to run before shipping.
