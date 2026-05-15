# `modules/gestures.sh`

## Purpose

Installs and configures `touchegg` for ChromeOS-like multi-finger
touchpad gestures (pinch zoom, 3-finger swipes for back/forward and
overview, 4-finger swipes for workspace and launcher).

## Function exported

`step_gestures`

## Inputs

- `ensure_apt_fresh` (helper from `setup.sh`).
- `$REPO_DIR/assets/configs/touchegg.conf` — the system-wide binding
  profile.
- `$SUDO_USER` (optional) — if set, the live oem session gets the
  touchegg client started for QA.

## Outputs

Installed packages:

- `wmctrl`, `xdotool` — used by gesture commands (`wmctrl -k on` for
  show-desktop, `xdotool` for some key-send fallbacks).
- `touchegg` — the gesture daemon and client.
- `xfdashboard` (optional; allowed to fail) — XFCE window overview
  used by the 3-finger swipe up gesture.

System files placed:

- `/etc/touchegg/touchegg.conf` — copied from
  `$REPO_DIR/assets/configs/touchegg.conf` with mode `644`.

Services enabled:

- `touchegg.service` — system daemon, `enable --now`.

Live session changes (only if `$SUDO_USER`):

- `touchegg --client` started for that user.

## The gesture set

The conf file binds:

| Gesture | Action | Mechanism |
|---|---|---|
| 2-finger pinch in | Zoom out (`Ctrl+-`) | `SEND_KEYS Control_L+minus` |
| 2-finger pinch out | Zoom in (`Ctrl+=`) | `SEND_KEYS Control_L+equal` |
| 3-finger swipe left | Browser back (`Alt+Left`) | `SEND_KEYS Alt_L+Left` |
| 3-finger swipe right | Browser forward (`Alt+Right`) | `SEND_KEYS Alt_L+Right` |
| 3-finger swipe up | Window overview | `RUN_COMMAND xfdashboard` |
| 3-finger swipe down | Show desktop | `RUN_COMMAND wmctrl -k on` |
| 4-finger swipe left | Previous workspace (`Ctrl+Alt+Left`) | `SEND_KEYS Control_L+Alt_L+Left` |
| 4-finger swipe right | Next workspace (`Ctrl+Alt+Right`) | `SEND_KEYS Control_L+Alt_L+Right` |
| 4-finger swipe up | Whisker menu launcher | `RUN_COMMAND xfce4-popup-whiskermenu` |

Touchpads that report only up to 3 fingers (older or low-end models)
will silently no-op the 4-finger gestures.

## Walkthrough

### 1. Apt install

```bash
ensure_apt_fresh
apt-get install -y wmctrl xdotool touchegg

if ! apt-get install -y xfdashboard; then
    echo "    [!] xfdashboard not available in apt — 3-finger swipe up gesture"
    echo "        will silently no-op."
fi
```

`xfdashboard` is intentionally in its own apt-call wrapped with
`if !`. The project is upstream-deprecated and absent from some newer
Mint repos. We don't want the *whole module* to fail just because the
window-overview gesture won't have an action.

### 2. Deploy bindings

```bash
mkdir -p /etc/touchegg
install -m 644 "$REPO_DIR/assets/configs/touchegg.conf" /etc/touchegg/touchegg.conf
```

`/etc/touchegg/touchegg.conf` is the system-wide profile. There is
also a per-user override location under `~/.config/touchegg/`, which
this toolkit does **not** use — the buyer is free to add one later if
they want different bindings.

### 3. Enable the daemon

```bash
systemctl enable --now touchegg.service 2>/dev/null || true
```

`touchegg`'s systemd unit comes with the apt package. `--now` starts
it immediately. The system daemon reads libinput and dispatches
gestures to per-user clients via D-Bus.

A `systemctl is-active --quiet touchegg.service` check is printed
afterwards so the technician sees green/red in the log.

### 4. Live-session client

```bash
if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null; then
    sudo -u "$SUDO_USER" pkill -f 'touchegg --client' 2>/dev/null || true
    sudo -u "$SUDO_USER" \
        DISPLAY="${DISPLAY:-:0}" \
        XAUTHORITY="$USER_HOME/.Xauthority" \
        touchegg --client 2>/dev/null &
fi
```

Same shape as `step_touchpad`'s imwheel launch: kill any pre-existing
client, start a fresh one for the live session. Without this the
technician can't QA gestures until a re-login.

## Why touchegg, not libinput-gestures?

`libinput-gestures` reads `/dev/input/event*` directly and requires
its user to be in the `input` group. For the OEM workflow this is a
problem: every buyer's user account would need to be added to `input`
post-handover, and the buyer doesn't have a route to do that without
the technician walking them through `usermod -aG input`.

`touchegg`'s split architecture (system daemon reads libinput, per-user
clients receive over D-Bus) means **no group changes are needed** for
the buyer. They just log in and gestures work.

## Notes

- The system-wide config is deployed *before* the daemon is enabled.
  Order matters: if the daemon starts and reads an empty config first,
  it ignores future config changes until restart. Starting after the
  file is in place avoids that race.
- The skel autostart entry that starts `touchegg --client` for every
  user (`/etc/skel/.config/autostart/touchegg-client.desktop`) was
  staged by `step_themes`.
- `wmctrl -k on` is the GNOME / Compiz "show desktop" toggle, which
  XFCE understands. Replacing it with `xdotool key super+d` works on
  Wayland but not consistently on XFCE/X11.

## Idempotency

Fully idempotent:

- `apt-get install -y` is a no-op for installed packages.
- `install -m 644` overwrites with identical content.
- `systemctl enable --now` is a no-op if already enabled and
  running.
- The `pkill` + restart of the client is the same as the first
  start.

## Uninstall counterpart

`step_uninstall`:

- `systemctl disable --now touchegg` (sub-step 1).
- `pkill 'touchegg --client'` (sub-step 1).
- `apt purge touchegg xfdashboard wmctrl xdotool` (sub-step 2).
- `rm /etc/touchegg/touchegg.conf`, `rmdir /etc/touchegg`
  (sub-step 7).
- Per-user `~/.config/autostart/touchegg-client.desktop` removed for
  every uid≥1000 (sub-step 13) and `/etc/skel/.config/autostart/
  touchegg-client.desktop` (sub-step 12).
