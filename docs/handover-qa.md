# Handover QA checklist

Run after a full pipeline **and after a reboot**. Tick every box; if any
fails, fix or re-apply the relevant step before shipping the machine.

The order roughly matches the boot-to-shutdown flow a technician would
go through anyway.

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
      detects a thumb drive **after a reboot**. If not, re-run option
      4 and reboot.
- [ ] Wi-Fi connects after suspend / resume:
  ```
  systemctl suspend
  ```
  then press a key, log back in, confirm Wi-Fi reconnects automatically.

## Touchpad

- [ ] Single-finger tap = left click.
- [ ] Two-finger tap = right click.
- [ ] Two-finger drag = natural scroll (page scrolls *with* the
      fingers, ChromeOS-style).
- [ ] Two-finger scroll feels noticeably slower than a default Mint
      install (the toolkit sets `Option "ScrollPixelDistance" "40"` —
      higher = slower; libinput default is ~15). To verify the property
      is live:
  ```
  TPID=$(xinput list | grep -iE 'touchpad|trackpad|synaptics|elan' \
         | grep -o 'id=[0-9]*' | head -1 | cut -d= -f2)
  xinput list-props "$TPID" | grep 'Scrolling Pixel Distance'
  ```
  → `libinput Scrolling Pixel Distance (NNN): 40`. Tune the value in
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
- [ ] GTK theme is `Mint-Y-Aqua`; icons are `Papirus`. Confirm via:
  ```
  xfconf-query -c xsettings -p /Net/ThemeName        # → Mint-Y-Aqua
  xfconf-query -c xsettings -p /Net/IconThemeName    # → Papirus
  ```
- [ ] A bottom dock panel (panel-2) is visible with exactly 11 icons,
      centered, in this order:
      Chrome, Settings, Files, VLC, Zoom, Gmail, Docs, Drive, Gemini,
      YouTube, Spotify.
      If an app's installer failed (e.g. Zoom download timed out), its
      icon will simply be absent from the dock.
- [ ] Clicking each dock icon opens the right app or web view.

## Chrome and web apps

- [ ] Chrome opens, logs in to a Google account, plays a YouTube video.
- [ ] All 11 web-app shortcuts (from the application menu, search for
      each):
  - [ ] Netflix
  - [ ] Prime Video
  - [ ] Disney+
  - [ ] Max
  - [ ] YouTube (also pinned to dock)
  - [ ] Spotify (also pinned to dock)
  - [ ] Gmail (also pinned to dock)
  - [ ] Google Docs (also pinned to dock)
  - [ ] Google Drive (also pinned to dock)
  - [ ] Gemini (also pinned to dock)
  - [ ] Chrome Remote Desktop

  Each should launch in its own Chrome window with no address bar
  (`--app=` mode) and the right icon in the taskbar.

- [ ] Opening any web app does **not** prompt for a keyring password
      (the launchers pass `--password-store=basic` so Chrome skips
      gnome-keyring). If a "Choose password for new keyring" dialog
      appears, the .desktop file was edited or the Exec line lost the
      flag — re-run option 8.
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

## Powerwash readiness

- [ ] Powerwash menu entry exists. Search the application menu for
      "Powerwash" — it should appear with a blue tile and a white
      refresh-arrow icon.
- [ ] Polkit policy is registered:
  ```
  pkaction --action-id org.linuxoem.powerwash.arm
  ```
  Exits with status `0` (silently). Non-zero means the policy is
  missing — re-run option 14.
- [ ] *Do not actually run Powerwash during QA.* Confirm the menu entry
      and the polkit policy only. The buyer is the one who runs it.

## Final OEM hand-off

- [ ] Reboot one more time.
- [ ] Double-click the **Prepare for shipping to end user** desktop
      icon (this triggers `oem-config-prepare` on the live oem
      session — Mint's built-in handover step, not part of this
      toolkit).
- [ ] Enter the OEM password.
- [ ] Wait for the *Ready for shipping* / shutdown screen, then power
      the machine off.

The next person to turn it on is the buyer. They will see the same
welcome wizard a brand-new Mint OEM install shows, then land on a fully
configured ChromeOS-like desktop with the Malta wallpaper, the bottom
dock panel, the keyboard layout the technician picked, and every shortcut.

---

## What to do if a check fails

| Check | Likely cause | Fix |
|---|---|---|
| Audio missing | `chromebook-linux-audio` setup did not detect the board | Re-run option 4 and read the installer's prompts carefully |
| Top-row keys wrong | `cros-keyboard-map` picked the wrong layout | Re-run option 4 and answer the layout question correctly |
| USB-C dead on 11th-gen+ | initramfs not rebuilt | `sudo update-initramfs -u -k all`, reboot |
| Wallpaper missing | First-run script didn't run | `ls ~/.config/.oem-first-run-done` — if present, delete it and log in/out |
| Dock (panel-2) missing | First-run script didn't run, or panel-2 check failed | Delete the marker (`rm ~/.config/.oem-first-run-done`) and re-login |
| Dock missing specific app | The referenced `.desktop` doesn't exist (e.g. Zoom download failed) | Re-run the relevant install (5, 6, 7, 8) then re-login or re-run option 9 |
| Gesture not firing | Touchpad firmware doesn't report that finger count | No fix — silently unsupported; 3-finger gestures should still work |
| Powerwash menu icon is generic | GTK icon cache stale | `sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor` |

Anything not in this table: read `/var/log/oem-setup.log`.
