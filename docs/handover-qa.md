# Handover QA checklist

Most checks below are partially automated by **`setup.sh` menu option 14**
(`step_diagnostics`) — see `/var/lib/oem-setup/diagnostics-report.txt`. This
page remains the master checklist and lists everything that still requires a
human.

Run after a full pipeline **and after a reboot**. Tick every box; if any
fails, fix or re-apply the relevant step before shipping the machine.

The order roughly matches the boot-to-shutdown flow a technician would
go through anyway.

---

## Boot (optional — menu option 2)

Use **menu option 2** only when you want Xubuntu/Ubuntu-style boot tweaks;
it is **not** part of menu option 1 (full pipeline). After running it,
**reboot**. To compare startup blocking units:

```bash
systemd-analyze time
systemd-analyze blame --no-pager | head -25
systemd-analyze critical-chain --no-pager | head -40
```

Menu option **14** writes excerpts under **Boot (systemd)** in
`/var/lib/oem-setup/diagnostics-report.txt`.

---

## Hardware

- [ ] Speakers play audio (YouTube test in Chrome).
- [ ] Headphone jack switches output automatically when a 3.5mm jack is
      plugged in.
- [ ] Microphone level moves in `pavucontrol` → Input Devices when you
      speak.
- [ ] Top-row keys (left to right) behave as expected:
  - [ ] Back / Forward / Refresh (browser shortcuts).
  - [ ] Brightness down / up.
  - [ ] Mute / Volume down / Volume up.
- [ ] All USB-A ports detect a thumb drive (mount + show in Thunar).
- [ ] On Intel 11th-gen and newer (TigerLake/AlderLake): USB-C port
      detects a thumb drive **after a reboot**. If not, re-run menu
      option 4 (hardware fixes) and reboot.
- [ ] Wi-Fi connects after suspend / resume:
  ```
  systemctl suspend
  ```
  then press a key, log back in, confirm Wi-Fi reconnects automatically.

## Touchpad

- [ ] Single-finger tap = left click; two-finger tap = right click.
- [ ] Single-finger **physical press** anywhere on the pad = left click;
      two-finger **physical press** = right click (not left/right
      zones). If presses still feel zoned, confirm libinput:
  ```
  TPID=$(xinput list | grep -iE 'touchpad|trackpad|synaptics|elan' \
         | grep -o 'id=[0-9]*' | head -1 | cut -d= -f2)
  xinput list-props "$TPID" | grep -E 'Tapping Enabled|Click Method Enabled'
  ```
  → `libinput Tapping Enabled (NNN): 1` and
  `libinput Click Method Enabled (NNN): 0, 1` (buttonareas off,
  clickfinger on).
- [ ] Two-finger drag = natural scroll (page scrolls *with* the
      fingers, ChromeOS-style).
- [ ] Two-finger scroll feels noticeably slower than default libinput
      (~15): the toolkit sets `Option "ScrollPixelDistance" "40"` in
      `40-chromebook-touchpad.conf` (higher = slower). To verify:
  ```
  TPID=$(xinput list | grep -iE 'touchpad|trackpad|synaptics|elan' \
         | grep -o 'id=[0-9]*' | head -1 | cut -d= -f2)
  xinput list-props "$TPID" | grep 'Scrolling Pixel Distance'
  ```
  → `libinput Scrolling Pixel Distance (NNN): 40`. Tune in
  `modules/touchpad.sh` (`OEM_SCROLL_PIXEL_DISTANCE`) if needed.
- [ ] All eight gestures:
  - [ ] 2-finger pinch in / out → zoom in / out (Ctrl+- / Ctrl+=).
  - [ ] 3-finger swipe left / right → browser back / forward
        (Alt+Left / Alt+Right).
  - [ ] 3-finger swipe up → window overview (`xfdashboard`).
  - [ ] 3-finger swipe down → show desktop (`wmctrl -k on`).
  - [ ] 4-finger swipe left / right → previous / next workspace.
  - [ ] 4-finger swipe up → whisker menu launcher.

If 4-finger gestures don't fire on a given board: the touchpad firmware
may not report 4-finger events. Three-finger gestures should always
work; the 4-finger ones silently no-op on unsupported hardware.

## Keyboard

- [ ] Pressing the keys printed on the keycaps types the expected
      characters (matches the layout chosen during
      `prompt_keyboard`).
- [ ] AltGr / dead keys work for accented characters in the chosen
      layout (if applicable).
- [ ] Terminal: pasting a multi-line block does **not** produce
      `0~...1~` garbage (bracketed-paste fix from `step_terminal`).

## Desktop & visuals

- [ ] Malta wallpaper is shown on every connected display (the
      first-run script applies it to every detected monitor).
- [ ] GTK and icon themes match **distro defaults** (this toolkit does
      not force Mint-Y, Papirus, or other theme packages). Optional sanity:
  ```
  xfconf-query -c xsettings -p /Net/ThemeName
  xfconf-query -c xsettings -p /Net/IconThemeName
  ```
- [ ] Plank (bottom dock) is visible with **up to** one icon per launcher
      whose `.desktop` exists. Order: App Finder, workspace overview
      (`xfdashboard`), Chrome, Settings, **Files** (Thunar — `thunar` or
      `org.xfce.thunar` .desktop), **software centre** (first match among
      Mint/Ubuntu `.desktop` names), VLC, Zoom, then web apps (Gmail, Docs,
      Sheets, Slides, Drive, Gemini, YouTube, Spotify) when those shortcuts
      exist. If an installer failed (e.g. Zoom), that icon is simply absent.
- [ ] **Workspace overview:** the workspace-overview item opens `xfdashboard`;
      the same action is bound to **3-finger swipe up** (Touchegg).
- [ ] **Chromebook top-row overview key** (often the “scale” icon next to
      brightness): should launch the same **`xfdashboard`** view. If it does
      nothing on your board, note the keysym with `xev` and extend
      `setup_workspace_overview_keys` in `oem-first-run.sh`.
- [ ] Clicking each dock icon opens the right app or web view.

## Chrome and web apps

- [ ] Chrome opens, logs in to a Google account, plays a YouTube video
      **without** a gnome-keyring / "new keyring password" dialog (`step_chrome`
      patches `google-chrome.desktop` with the same `OEM_CHROME_EXEC_FLAGS` as
      web apps; re-run menu option 5 if a Chrome package upgrade restored the
      vendor desktop file).
- [ ] All 13 web-app shortcuts (from the application menu, search for
      each):
  - [ ] Netflix
  - [ ] Prime Video
  - [ ] Disney+
  - [ ] Max
  - [ ] YouTube (also pinned to dock)
  - [ ] Spotify (also pinned to dock)
  - [ ] Gmail (also pinned to dock)
  - [ ] Google Docs (also pinned to dock)
  - [ ] Google Sheets (also pinned to dock)
  - [ ] Google Slides (also pinned to dock)
  - [ ] Google Drive (also pinned to dock)
  - [ ] Gemini (also pinned to dock)
  - [ ] Chrome Remote Desktop

  Each should launch in its own Chrome window with no address bar
  (`--app=` mode) and the right icon in the taskbar.

- [ ] Opening any web app does **not** prompt for a keyring password
      (`OEM_CHROME_EXEC_FLAGS` / `--password-store=basic`; same as main
      Chrome after `step_chrome`). If a "Choose password for new keyring" dialog
      appears, the `Exec=` line lost the flag — re-run option 5 (Chrome) and/or
      option 8 (web apps).
- [ ] The web-app window uses the thin auto-hide overlay scrollbar,
      not the always-visible classic scrollbar (we pass
      `--enable-features=OverlayScrollbar`). Hover near the right
      edge: a slim track should fade in, then fade out a second after
      you stop scrolling.

## Power management

- [ ] `systemctl status tlp.service` → `active (exited)` (TLP is a
      oneshot at boot).
- [ ] `systemctl status touchegg.service` → `active (running)`.
- [ ] Closing the lid suspends; opening it resumes.

## Final OEM hand-off

- [ ] Reboot one more time.
- [ ] Double-click the **Prepare for shipping to end user** desktop
      icon (this triggers `oem-config-prepare` on the live oem
      session — the distro OEM handover step, not part of this
      toolkit).
- [ ] Enter the OEM password.
- [ ] Wait for the *Ready for shipping* / shutdown screen, then power
      the machine off.

The next person to turn it on is the buyer. They will see the same
welcome wizard as a fresh OEM install, then land on a configured desktop
with the Malta wallpaper, Plank dock, keyboard layout the technician picked,
and every shortcut.

---

## What to do if a check fails

| Check | Likely cause | Fix |
|---|---|---|
| Audio missing | `chromebook-linux-audio` setup did not detect the board | Re-run option 4 and read the installer's prompts carefully |
| Top-row keys wrong | `cros-keyboard-map` picked the wrong layout | Re-run option 4 and answer the layout question correctly |
| USB-C dead on 11th-gen+ | initramfs not rebuilt | `sudo update-initramfs -u -k all`, reboot |
| Wallpaper missing | First-run script didn't run | `ls ~/.config/.oem-first-run-done` — if present, delete it and log in/out |
| Dock / Plank missing or short an icon | First-run script didn't run, or a `.desktop` was missing at first-run time | Delete the marker (`rm ~/.config/.oem-first-run-done`) and re-login; ensure `step_gestures_and_workspaces` ran before `step_themes` when reprovisioning |
| Dock missing specific app | The referenced `.desktop` doesn't exist (e.g. Zoom download failed) | Re-run the relevant install (5–8) then re-login or re-run option 9 |
| Gesture not firing | Touchpad firmware doesn't report that finger count | No fix — silently unsupported; 3-finger gestures should still work |

Anything not in this table: read `/var/log/oem-setup.log` (best-effort transcript
— upstream hardware installers are terminal-only).
