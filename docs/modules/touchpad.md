# `modules/touchpad.sh`

## Purpose

Three touchpad concerns in one module:

1. **Natural scrolling** — page scrolls in the same direction as the
   fingers move (ChromeOS / macOS style).
2. **Persistent xorg.conf snippet** — survives reboot and applies to
   every user on every login.
3. **imwheel scroll multiplier** — 3x the default scroll-event delta,
   because Chromebook touchpads default to a frustratingly slow
   scroll on Linux.

## Function exported

`step_touchpad`

## Inputs

- `xinput` (installed by `step_updates`).
- `imwheel` (installed by `step_updates`).
- `$SUDO_USER` (optional) — if set, the live oem session gets imwheel
  immediately for QA.
- `$DISPLAY` (optional) — defaults to `:0`.
- `$REPO_DIR/skel/.imwheelrc`.

## Outputs

- `/etc/X11/xorg.conf.d/40-chromebook-touchpad.conf` — system-wide
  libinput config for any matching touchpad.
- For the live oem user: `~/.imwheelrc` (copied from
  `$REPO_DIR/skel/.imwheelrc`).
- A running `imwheel` process for the live oem user.

## Walkthrough

### 1. Apply natural scrolling to the live session

```bash
local TP_ID
TP_ID=$(xinput list 2>/dev/null \
    | grep -iE 'touchpad|trackpad|synaptics|elan' \
    | grep -o 'id=[0-9]*' | head -1 | cut -d= -f2 || true)

if [ -n "$TP_ID" ]; then
    xinput set-prop "$TP_ID" "libinput Natural Scrolling Enabled" 1 2>/dev/null || true
fi
```

Discovery via `xinput list` — matches "touchpad", "trackpad",
"synaptics", or "elan" case-insensitively (covers every Chromebook
touchpad family I've seen). If no match: print a warning and skip
the live apply. The xorg.conf snippet (next sub-step) handles the
reboot case anyway.

### 2. Persistent xorg.conf snippet

```bash
cat > /etc/X11/xorg.conf.d/40-chromebook-touchpad.conf << 'EOF'
Section "InputClass"
    Identifier      "chromebook-touchpad"
    MatchIsTouchpad "on"
    Driver          "libinput"
    Option "NaturalScrolling"              "true"
    Option "AccelProfile"                  "adaptive"
    Option "HighResolutionWheelScrolling"  "false"
    Option "Tapping"                       "on"
    Option "TappingDrag"                   "on"
    Option "DisableWhileTyping"            "on"
EndSection
EOF
```

Six options worth understanding:

| Option | Why |
|---|---|
| `NaturalScrolling true` | Page follows fingers. |
| `AccelProfile adaptive` | Cursor accel speeds up on rapid movement — what users expect. |
| `HighResolutionWheelScrolling false` | **The single most important line.** Chromebook HID touchpads report scroll events twice when HiRes wheel scrolling is on (once as a hi-res event, once as a coarse fallback) — confirmed on HP / Lenovo / ELAN devices. Turning it off makes scroll behave consistently. |
| `Tapping on` | Tap-to-click. |
| `TappingDrag on` | Tap-and-drag (double-tap then slide). |
| `DisableWhileTyping on` | The classic palm-rejection-while-typing toggle. |

`MatchIsTouchpad on` makes the section apply to any libinput-recognised
touchpad, regardless of vendor or product ID. Future Chromebook
touchpads will just work.

### 3. imwheel for the live session

```bash
if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null; then
    local USER_HOME
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

    install -m 644 -o "$SUDO_USER" -g "$SUDO_USER" \
        "$REPO_DIR/skel/.imwheelrc" "$USER_HOME/.imwheelrc"

    sudo -u "$SUDO_USER" pkill -x imwheel 2>/dev/null || true
    sudo -u "$SUDO_USER" \
        DISPLAY="${DISPLAY:-:0}" \
        XAUTHORITY="$USER_HOME/.Xauthority" \
        imwheel 2>/dev/null &
fi
```

- `install` is used instead of `cp` so we can set the right owner,
  group, and mode in one atomic call.
- `pkill -x imwheel` kills any previously-started instance — the new
  one will read the freshly-installed `.imwheelrc`.
- `imwheel … &` backgrounds the process. `DISPLAY` and `XAUTHORITY`
  are set in the `sudo -u` env so the child connects to the right X
  server.

For every new user account, the same `.imwheelrc` lives in `/etc/skel/`
(staged by `step_themes`), and the `imwheel.desktop` autostart entry
launches it on each XFCE login.

## Why imwheel?

libinput exposes no scroll-speed property. Its `AccelSpeed` option
affects only cursor movement, not scroll delta. After two days of
experiments:

- `evdev` driver tweaks: ineffective, libinput overrides.
- `synclient` (synaptics): only works on the synaptics driver,
  Mint defaults to libinput.
- `xinput set-prop "Scroll Multiplier"`: doesn't exist for libinput.
- imwheel: works on every board tested.

imwheel intercepts X11 scroll events and re-emits them N times.
`skel/.imwheelrc` says N=3. To change the multiplier system-wide,
edit that file before running the toolkit.

## Notes

- `set-prop` may return non-zero if the touchpad doesn't expose the
  property (e.g. it's already been claimed by Wayland or a different
  driver) — hence the `|| true`.
- imwheel is intentionally **not** a system service. It's a per-user
  X11 client because that's the only context where it can grab the
  scroll events.
- The xorg.conf snippet is in `/etc/X11/xorg.conf.d/` (system-wide),
  not under `/etc/skel/`. Touchpad behaviour is a hardware concern,
  not a per-user preference.

## Idempotency

Fully idempotent:

- `xinput set-prop` is a value-set; re-applying the same value is a
  no-op.
- `cat > … << EOF` truncates and rewrites the xorg.conf file with
  identical content.
- `install` overwrites; idempotent.
- `pkill -x imwheel` is allowed to "fail" (no matching process).
- A re-launch of `imwheel` after `pkill` is the same as the first
  launch.

## Uninstall counterpart

`step_uninstall`:

- `pkill imwheel` (sub-step 1).
- `apt purge imwheel` (sub-step 2).
- `rm /etc/X11/xorg.conf.d/40-chromebook-touchpad.conf` (sub-step 7).
- Remove per-user `.imwheelrc` from every uid≥1000 (sub-step 13) and
  `/etc/skel/.imwheelrc` (sub-step 12).
