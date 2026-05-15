# `modules/touchpad.sh`

## Purpose

Two touchpad concerns in one module:

1. **Natural scrolling** — page scrolls in the same direction as the
   fingers move (ChromeOS / macOS style).
2. **Slower-than-default two-finger scroll** — Chromebook touchpads
   emit scroll events very densely; out of the box that feels frantic
   in a browser. We tell libinput "require more finger travel per
   scroll event" so the same physical drag covers less distance on
   screen.

(There used to be a third concern — an `imwheel`-based **3x scroll
multiplier** — that has been removed. It made scrolling *faster* than
default, which is the opposite of what the OEM workflow wants. See the
removal note at the bottom of this document for the migration story.)

## Function exported

`step_touchpad`

## Module-level constant

```bash
OEM_SCROLL_PIXEL_DISTANCE=40
```

The pixel distance a finger has to travel on the touchpad to emit one
scroll event. libinput's default is ~15. Higher = slower scroll.
**40** was picked as a comfortable browser feel on Lenovo / HP / Acer
Chromebook touchpads. Bump it higher (e.g. 60) for even slower scroll,
or lower it toward 15 for faster.

## Inputs

- `xinput` (installed by `step_updates`).
- `$SUDO_USER` (optional) — if set, the live oem session has the
  scroll properties applied immediately for QA.
- `$DISPLAY` (optional) — defaults to `:0`.

## Outputs

- `/etc/X11/xorg.conf.d/40-chromebook-touchpad.conf` — system-wide
  libinput config for any matching touchpad.
- For the live oem session (if `$SUDO_USER` is set):
  - `xinput set-prop "$TP_ID" "libinput Natural Scrolling Enabled" 1`.
  - `xinput set-prop "$TP_ID" "libinput Scrolling Pixel Distance" 40`.

## Walkthrough

### 1. Persistent xorg.conf.d snippet

```bash
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/40-chromebook-touchpad.conf << EOF
Section "InputClass"
    Identifier      "chromebook-touchpad"
    MatchIsTouchpad "on"
    Driver          "libinput"
    Option "NaturalScrolling"      "true"
    Option "AccelProfile"          "adaptive"
    Option "Tapping"               "on"
    Option "TappingDrag"           "on"
    Option "DisableWhileTyping"    "on"
    Option "ScrollPixelDistance"   "${OEM_SCROLL_PIXEL_DISTANCE}"
EndSection
EOF
```

Six options worth understanding:

| Option | Why |
|---|---|
| `NaturalScrolling true` | Page follows fingers. |
| `AccelProfile adaptive` | Cursor accel speeds up on rapid movement — what users expect. |
| `Tapping on` | Tap-to-click. |
| `TappingDrag on` | Tap-and-drag (double-tap then slide). |
| `DisableWhileTyping on` | The classic palm-rejection-while-typing toggle. |
| `ScrollPixelDistance 40` | **The single most important line.** Default is ~15. Larger value = the finger has to travel further to fire one scroll event = slower scroll. Tuned to roughly halve the dense scroll feed Chromebook touchpads emit. |

`MatchIsTouchpad on` makes the section apply to any libinput-recognised
touchpad, regardless of vendor or product ID. Future Chromebook
touchpads will just work.

### 2. Live-session apply via xinput

```bash
TP_ID=$(xinput list 2>/dev/null \
    | grep -iE 'touchpad|trackpad|synaptics|elan' \
    | grep -o 'id=[0-9]*' | head -1 | cut -d= -f2 || true)

if [ -n "$TP_ID" ]; then
    xinput set-prop "$TP_ID" "libinput Natural Scrolling Enabled" 1 \
        2>/dev/null || true
    xinput set-prop "$TP_ID" "libinput Scrolling Pixel Distance" \
        "$OEM_SCROLL_PIXEL_DISTANCE" 2>/dev/null \
        || echo "[!] property not exposed by this driver"
fi
```

Discovery via `xinput list` matches "touchpad", "trackpad",
"synaptics", or "elan" case-insensitively (covers every Chromebook
touchpad family I've seen). The `xinput set-prop` calls push the same
values that the xorg.conf.d snippet will use after a reboot, so the
technician feels the change *during the same QA session* without
needing an X restart.

If a given libinput build doesn't expose `Scrolling Pixel Distance`
(very old versions only), the second `set-prop` returns non-zero and
we print a one-line warning. The xorg.conf snippet still applies on
the next boot.

## Why ScrollPixelDistance, not imwheel?

libinput exposes no scroll-*speed* knob, but it does expose a scroll-
*granularity* knob. `ScrollPixelDistance` is exactly that: the pixel
distance the finger has to drag to fire one scroll event. Doubling it
roughly halves perceived scroll speed.

The previous design used `imwheel` to *multiply* scroll events 3x
("Chromebook touchpads scroll too slowly"). It was the wrong call —
in QA the multiplied scroll felt frantic, especially in browser long
pages. Removing imwheel and slowing libinput's native granularity
gives the OEM the calmer feel the workflow wants.

## Notes

- `set-prop` may return non-zero if the touchpad doesn't expose the
  property (e.g. it's already been claimed by Wayland or a different
  driver) — hence the `|| true`.
- The xorg.conf snippet is in `/etc/X11/xorg.conf.d/` (system-wide),
  not under `/etc/skel/`. Touchpad behaviour is a hardware concern,
  not a per-user preference.
- imwheel is no longer installed by `step_updates` and the autostart
  entry has been removed from `skel/`. `step_uninstall` still purges
  the imwheel package as a courtesy to anyone upgrading from an
  earlier revision of this toolkit.

## Idempotency

Fully idempotent:

- `cat > … << EOF` truncates and rewrites the xorg.conf file with
  identical content.
- `xinput set-prop` is a value-set; re-applying the same value is a
  no-op.

## Uninstall counterpart

`step_uninstall`:

- `rm /etc/X11/xorg.conf.d/40-chromebook-touchpad.conf` (sub-step 7).
- `apt purge imwheel` (sub-step 2) — backwards-compat cleanup for
  systems that had the old toolkit revision installed.
- `pkill imwheel` (sub-step 1) — ditto.
- Remove per-user `.imwheelrc` from every uid≥1000 (sub-step 13) and
  `/etc/skel/.imwheelrc` (sub-step 12) — `rm -f` is a no-op on the
  current revision (those files no longer exist) and a clean-up on
  legacy installs.
