# `modules/themes.sh`

## Purpose

Wires together the visual concerns that make the desktop look and feel
like ChromeOS, using fully Mint-shipped or apt-available components:

1. **Mint-Y-Aqua GTK theme** — ships with `mint-themes`, always present
   on Linux Mint XFCE; no download required.
2. **Papirus icon theme** — installed from apt; rounded, modern, close
   in spirit to ChromeOS's icon family.
3. **Plank dock** — bottom-centred dock seeded at first login by
   `oem-first-run.sh` (`plank` from apt).
4. **Malta wallpaper** — deployed to `/usr/share/backgrounds/oem-setup/`
   and applied per-user by the first-run script.
5. **Per-user first-run script** — applies wallpaper, theme, and Plank on
   first XFCE login; moves panel-1 to the top, removes its tasklist and
   default Firefox / Terminal / Thunar launchers, then self-deletes its
   autostart entry.

## Function exported

`step_themes`

(Plus the internal helper `oem_user_xrun`.)

## Inputs

- `$REPO_DIR` (for `assets/wallpapers/malta.jpg`,
  `assets/scripts/oem-first-run.sh`, and the entire `skel/` tree).
- `$SUDO_USER` (optional) — if set, the live oem session has the
  theme applied immediately for QA.
- `ensure_apt_fresh` (helper from `setup.sh`).

## Outputs

Installed packages:

- `papirus-icon-theme` from apt.
- `gtk2-engines-murrine` from apt (GTK2 engine; already installed by
  `step_updates`, but `themes.sh` also requests it via `ensure_apt_fresh`
  as a safety net).

System-wide files placed:

- `/usr/share/backgrounds/oem-setup/malta.jpg` — wallpaper file.
- `/usr/local/bin/oem-first-run.sh` — per-user applier (mode `755`).
- The entire `/etc/skel/` tree from `$REPO_DIR/skel/.` (`cp -r`).

Live session changes (only when `$SUDO_USER` is set):

- Skel autostart entries (`oem-first-run.desktop`,
  `touchegg-client.desktop`) copied into `~SUDO_USER/.config/autostart/`
  and chowned to `$SUDO_USER`.
- `xsettings.xml` copied into
  `~SUDO_USER/.config/xfce4/xfconf/xfce-perchannel-xml/`.
- `xfconf-query -c xsettings -p /Net/ThemeName     -s Mint-Y-Aqua`.
- `xfconf-query -c xsettings -p /Net/IconThemeName -s Papirus`.
- `xfconf-query -c xfwm4     -p /general/theme     -s Mint-Y-Aqua`.
- `pkill xfsettingsd` + `xfsettingsd --replace` (forces daemon to
  serve the new values rather than its cached state).
- Inline execution of `/usr/local/bin/oem-first-run.sh` — applies
  wallpaper, adjusts panel-1, strips default panel launchers, seeds Plank
  without waiting for a re-login.

## Walkthrough

### 1. Install packages

```bash
ensure_apt_fresh
apt-get install -y papirus-icon-theme gtk2-engines-murrine
```

`Mint-Y-Aqua` ships with `mint-themes`, which is always installed on
Mint — no apt install needed for the theme itself.

### 2. Wallpaper file deploy

```bash
mkdir -p /usr/share/backgrounds/oem-setup
cp "$REPO_DIR/assets/wallpapers/malta.jpg" \
   /usr/share/backgrounds/oem-setup/malta.jpg
```

Placed in its own subdirectory so Mint's backgrounds package cannot
overwrite it.

### 3. Deploy and stage the first-run script

```bash
install -m 755 "$REPO_DIR/assets/scripts/oem-first-run.sh" \
               /usr/local/bin/oem-first-run.sh

cp -r "$REPO_DIR/skel/." /etc/skel/
```

`/etc/skel` is consulted only when `useradd` creates a new account.
The skel tree contains `oem-first-run.desktop` (autostart entry) and
`xsettings.xml` (GTK theme default) so every buyer's new account
inherits the correct visual defaults automatically.

### 4. Mirror skel + live-apply (when `$SUDO_USER` is set)

Because the `oem` user pre-exists and never gets the skel treatment,
the module mirrors the relevant files explicitly and pushes the values
to the running XFCE session:

```bash
SUDO_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

# Copy autostart entries and xsettings.xml
for f in oem-first-run.desktop touchegg-client.desktop; do
    cp "/etc/skel/.config/autostart/$f" "$SUDO_HOME/.config/autostart/$f"
done
cp -f /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml \
      "$SUDO_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"
chown -R "$SUDO_USER:$SUDO_USER" "$SUDO_HOME/.config/autostart" \
                                  "$SUDO_HOME/.config/xfce4"

# Push theme values to the running session
oem_user_xrun "$SUDO_USER" xfconf-query -c xsettings -p /Net/ThemeName     -s "Mint-Y-Aqua"
oem_user_xrun "$SUDO_USER" xfconf-query -c xsettings -p /Net/IconThemeName -s "Papirus"
oem_user_xrun "$SUDO_USER" xfconf-query -c xfwm4     -p /general/theme     -s "Mint-Y-Aqua"

# Restart xfsettingsd so the new values propagate to running apps
sudo -u "$SUDO_USER" pkill -x xfsettingsd || true
sleep 0.3
oem_user_xrun "$SUDO_USER" xfsettingsd --replace &

# Apply wallpaper + create dock panel (inline first-run)
oem_user_xrun "$SUDO_USER" /usr/local/bin/oem-first-run.sh
```

Three things worth knowing:

1. **The xfwm4 theme must be set explicitly.** Setting only
   `xsettings /Net/ThemeName` changes GTK widget colours but leaves
   the window-decoration theme as the XFCE default — which causes the
   "theme has no effect whatsoever" symptom.
2. **xfsettingsd must be replaced**, not just signalled. It caches
   xsettings values and serves them on demand; without a restart,
   already-running apps keep the old theme.
3. **Running oem-first-run.sh inline** applies the wallpaper, panel-1
   layout (including removing default Firefox, terminal, and Thunar icons
   from the top bar), and seeds Plank in the live session without waiting
   for a re-login. The marker file (`~/.config/.oem-first-run-done`) that
   the script writes at the end makes the skel autostart entry silently
   no-op on all subsequent logins.

## The `oem_user_xrun` helper

```bash
oem_user_xrun() {
    local user="$1"; shift
    local home dbus_addr
    home=$(getent passwd "$user" | cut -d: -f6)

    local pid
    pid=$(pgrep -u "$user" -x xfsettingsd 2>/dev/null | head -1 || true)
    [ -z "$pid" ] && pid=$(pgrep -u "$user" -x xfce4-session 2>/dev/null | head -1 || true)

    if [ -n "$pid" ] && [ -r "/proc/$pid/environ" ]; then
        dbus_addr=$(tr '\0' '\n' < "/proc/$pid/environ" \
                    | awk '/^DBUS_SESSION_BUS_ADDRESS=/{ print substr($0, index($0,"=")+1); exit }')
    fi

    sudo -u "$user" env \
        HOME="$home" USER="$user" LOGNAME="$user" \
        PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        DISPLAY="${DISPLAY:-:0}" \
        XAUTHORITY="$home/.Xauthority" \
        DBUS_SESSION_BUS_ADDRESS="${dbus_addr:-}" \
        "$@"
}
```

Three environment variables are mandatory for xfconf-query to work in
the live session:

- `DISPLAY` — which X display to talk to.
- `XAUTHORITY` — the user's Xauth cookie file.
- `DBUS_SESSION_BUS_ADDRESS` — the per-user D-Bus session bus that
  `xfconfd` is listening on. This is discovered by reading
  `/proc/<pid>/environ` of a running session process.

`HOME` is also set explicitly so that any `~/.config` writes by the
called command land in the user's home, not `/root`.

## Notes

- `Mint-Y-Aqua` is one of the colour variants that ships with
  `mint-themes`. Others (`Mint-Y`, `Mint-Y-Blue`, etc.) are equally
  available. To change the colour variant, update the theme name in:
  `modules/themes.sh`, `skel/.config/xfce4/xfconf/xfce-perchannel-xml/
  xsettings.xml`, and `assets/scripts/oem-first-run.sh`.
- No dconf system database is written. The previous revision used
  `/etc/dconf/db/local.d/00-plank` to force dock contents system-wide.
  The current design manages the dock and panel-1 quick-launch cleanup
  entirely per-user in `oem-first-run.sh`, which is simpler and avoids the dconf-service
  restart race condition seen during the first QA run.

## Idempotency

Fully idempotent:

- `apt-get install -y` is a no-op for already-installed packages.
- `cp` overwrites with identical content.
- `cat > … << EOF` (wallpaper directory) is idempotent.
- The live-apply block runs `pkill xfsettingsd` and restarts it — safe
  to repeat.
- `oem-first-run.sh` checks `~/.config/.oem-first-run-done` at startup
  and exits immediately if it exists, so the inline call is a no-op on
  re-runs of `step_themes` (after the first time).

## Uninstall counterpart

`step_uninstall` (sub-steps 2, 8, 12, 13):

- **Papirus (2)**: `apt purge papirus-icon-theme`.
- **Wallpaper + first-run script (8)**: `rm -rf /usr/share/backgrounds/
  oem-setup`, `rm /usr/local/bin/oem-first-run.sh`.
- **`/etc/skel` cleanup (12)**: `rm` `oem-first-run.desktop`,
  `touchegg-client.desktop`, `xsettings.xml`; `rmdir` empty parents.
- **Per-user cleanup (13)**: `rm` `.oem-first-run-done`, autostart
  entries, and launcher dirs under `~/.config/xfce4/panel/launcher-NNN`
  where NNN ≥ 100 (IDs used by the toolkit's dock). xfconf panel-2 keys
  are removed via `xfconf-query -p /panels/panel-2 -r -R`.
