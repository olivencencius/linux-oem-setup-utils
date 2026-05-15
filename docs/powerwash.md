# Powerwash — end-to-end flow

The buyer-facing factory reset is the most multi-stage feature in the
toolkit. It crosses four files, two privilege boundaries, two boots, and
the polkit / systemd subsystems. This page is the single place to
understand it.

If you only need *how the install step works*, read
[`modules/powerwash.md`](./modules/powerwash.md). Everything else is here.

---

## What the buyer sees

1. Application menu → search for "Powerwash" (or "reset").
2. A blue tile with a white refresh-arrow icon labelled **Powerwash**.
3. Clicking it shows a zenity question dialog: *"Powerwash will erase
   ALL personal data on this device. … Continue?"*
4. After Continue, a second zenity entry dialog asks them to type
   **`POWERWASH`** in capital letters.
5. After the typed phrase, the standard polkit admin-auth prompt
   appears: *"Authentication is required to erase this device and
   return it to its factory configuration."*
6. After successful auth, an info dialog says *"The device will
   restart now to finish powerwashing."* The machine reboots ~2 s
   later.
7. Next boot: before any login screen appears, the device wipes
   accounts and re-arms the OEM wizard. The buyer briefly sees a
   black-screen-with-text systemd boot, then the machine reboots
   once more.
8. The next boot lands on the same welcome wizard the buyer saw on
   day one.

The whole flow is intentionally heavy on confirmation up front
(question → typed phrase → polkit) and zero-confirmation once armed:
once a buyer hits "Authenticate", the wipe will happen, even if power
is removed and restored.

---

## The four files

```
oem-powerwash.sh                      user-mode entry          (/usr/local/bin)
oem-powerwash-arm.sh                  pkexec target            (/usr/local/sbin)
oem-powerwash-finalize.sh             boot-time wipe           (/usr/local/sbin)
oem-powerwash-finalize.service        systemd one-shot         (/etc/systemd/system)
```

Two supporting files:

```
oem-powerwash.desktop                 menu entry               (/usr/share/applications)
oem-powerwash.policy                  polkit policy            (/usr/share/polkit-1/actions)
```

And the runtime state file used as the trigger between user space and
the boot service:

```
/var/lib/oem-setup/powerwash.flag     created by arm, deleted by finalize
```

All six are deployed by `step_powerwash` (from `modules/powerwash.sh`).
For a flat install-path table see [`assets.md`](./assets.md).

---

## Stage 1 — `oem-powerwash.sh` (the buyer)

Runs as the buyer (unprivileged). Refuses to run as root — the GUI
dialogs must own the user's X session.

Three sub-stages:

### 1a. Detect a dialog backend

```bash
if command -v zenity >/dev/null 2>&1 \
   && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then
    USE_GUI=1
fi
```

Falls back to plain TTY prompts if no display is available — which is
mostly belt-and-braces, because the only way to launch this is from
the application menu inside a graphical session.

### 1b. Confirm twice

- **Question dialog** with a multi-paragraph warning. Default button is
  Cancel. The user must click Continue.
- **Entry dialog** that demands the literal string `POWERWASH` (case
  sensitive). Anything else cancels.

If either is cancelled, the script exits 0 with no side effects.

### 1c. Escalate via `pkexec`

```bash
if pkexec /usr/local/sbin/oem-powerwash-arm.sh; then
    zenity --info --text "The device will restart now to finish powerwashing." &
    exit 0
else
    zenity --error --text "Powerwash was not started …"
    exit "$?"
fi
```

Important subtlety: the "device will restart" notice is shown **only
after** `pkexec` returns success. If the buyer cancels the admin auth
prompt, `pkexec` exits non-zero, an error dialog is shown instead, and
nothing happens.

A naïve implementation would show the "restarting" notice before
calling `pkexec` — and a buyer who cancelled would be staring at a
notice promising a reboot that never came.

The `zenity --info &` is backgrounded because `oem-powerwash-arm.sh`
will reboot the machine ~2 s later. We don't want a foreground dialog
to block the reboot.

---

## Stage 2 — `oem-powerwash-arm.sh` (root via pkexec)

Tiny, ~50 lines. Sole job: write the flag the boot service watches for,
enable the unit, reboot.

```
1. Refuse to run if EUID != 0.
2. Atomically write /var/lib/oem-setup/powerwash.flag
   with requested_at, requested_by_uid, requested_by_name.
3. systemctl daemon-reload   (no-op on most boots, defensive)
4. systemctl enable oem-powerwash-finalize.service
5. sleep 2   (let the caller's "restarting" dialog render)
6. systemctl reboot
```

The atomic-write step (`mktemp` + `mv`) is partly defensive: the
finalize service only checks for the flag file's *existence*, so a
half-written file would still trigger it. But a clean file makes
`/var/log/oem-powerwash.log` greppable for who armed the wipe and
when.

The polkit action `org.linuxoem.powerwash.arm` whitelists exactly
`/usr/local/sbin/oem-powerwash-arm.sh` as the pkexec target. Anything
else under `/usr/local/sbin/` cannot be invoked under this action.

---

## Stage 3 — the polkit policy

`assets/configs/oem-powerwash.policy` installed to
`/usr/share/polkit-1/actions/org.linuxoem.powerwash.policy`.

Key elements:

```xml
<action id="org.linuxoem.powerwash.arm">
  <description>Powerwash this device</description>
  <message>Authentication is required to erase this device and return
           it to its factory configuration. This cannot be undone.</message>
  <icon_name>oem-powerwash</icon_name>
  <defaults>
    <allow_any>auth_admin</allow_any>
    <allow_inactive>auth_admin</allow_inactive>
    <allow_active>auth_admin</allow_active>
  </defaults>
  <annotate key="org.freedesktop.policykit.exec.path">/usr/local/sbin/oem-powerwash-arm.sh</annotate>
  <annotate key="org.freedesktop.policykit.exec.allow_gui">true</annotate>
</action>
```

Notes:

- `auth_admin` for all three contexts means *every* invocation requires
  fresh admin authentication. No persistent caching, no "remember for
  this session". This is intentional — even a privileged buyer cannot
  re-arm a powerwash by accident.
- The `<icon_name>` makes the polkit prompt show the Powerwash icon
  instead of a generic shield, so the buyer can visually confirm what
  they're authorising.
- `allow_gui="true"` lets the action be invoked from a graphical session
  (the default is to refuse).

`pkaction --action-id org.linuxoem.powerwash.arm` returning 0 is the
QA check that confirms the policy is registered. See
[`handover-qa.md`](./handover-qa.md).

---

## Stage 4 — `oem-powerwash-finalize.service` (systemd)

```ini
[Unit]
Description=Finalize OEM powerwash (wipe accounts, re-arm first-boot wizard)
DefaultDependencies=no
After=local-fs.target systemd-tmpfiles-setup.service
Before=display-manager.service lightdm.service gdm.service sddm.service multi-user.target
ConditionPathExists=/var/lib/oem-setup/powerwash.flag

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/oem-powerwash-finalize.sh
RemainAfterExit=no
StandardOutput=journal+console
StandardError=journal+console
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target
```

Critical ordering:

- **`After=local-fs.target`** — wait for `/var` (where the flag lives)
  and `/home` (which we are about to wipe) to be mounted.
- **`Before=display-manager.service lightdm.service gdm.service sddm.service`** —
  run *before* any login prompt. We are about to delete every user
  account; we cannot have someone logged in.
- **`Before=multi-user.target`** — also before all the other multi-user
  services that might open files in homes.
- **`ConditionPathExists=`** — without the flag, the service skips
  silently. Defence-in-depth: even if the unit gets enabled by
  accident, no flag means no wipe.
- **`Type=oneshot`** + `RemainAfterExit=no` — runs once on this boot
  and goes away.
- **`StandardOutput=journal+console`** — boot-time output is visible on
  the TTY so a technician watching the screen can see progress, AND it
  goes to the journal for after-the-fact debugging.
- **`TimeoutStartSec=600`** — 10 minutes. Wiping ten 200-GB home
  directories can take a while; the default 90s is too short.

---

## Stage 5 — `oem-powerwash-finalize.sh` (root, no display manager)

Three phases. Output is appended to `/var/log/oem-powerwash.log`.

### 5a. Wipe every regular user

```bash
while IFS=: read -r name _ uid _ _ home _; do
    [ "$uid" -ge 1000 ] && [ "$uid" -lt 65534 ] || continue
    pkill -KILL -u "$name" 2>/dev/null || true
    sleep 1
    if ! userdel -r -f "$name" 2>/dev/null; then
        userdel -f "$name" 2>/dev/null || true
        [ -d "$home" ] && rm -rf "$home"
    fi
done < /etc/passwd
```

- Range `uid >= 1000 && < 65534` covers human users and excludes
  `nobody` (`65534`).
- `pkill -KILL -u "$name"` is for the unlikely case some process from
  that user is still running (a leftover systemd-user manager, an
  agetty, etc.). The service runs before display managers, so this is
  defence in depth.
- `userdel -r -f` deletes the account and its home in one go. The
  `userdel`-without-`-r` fallback handles edge cases where `-r` fails
  (e.g. a stale mount inside the home), and we then `rm -rf "$home"`
  to make sure nothing is left.
- Then orphaned groups (gid ≥ 1000 with no remaining members) are
  removed.

### 5b. Re-arm the OEM wizard

```bash
if oem-config-prepare --quiet 2>&1; then …
elif oem-config-prepare         2>&1; then …
else echo "[!] oem-config-prepare returned non-zero …"; fi
```

`oem-config-prepare` is the Ubuntu/Mint command that puts the machine
back into "first boot" mode — on the next display-manager start it
runs `oem-config-gtk` instead of the normal login, which is the same
welcome wizard the buyer saw on day one.

`--quiet` is tried first; some older `oem-config` versions don't have
it and exit non-zero on unknown flags. In that case we retry without
the flag. If the binary is missing entirely, the buyer will land on
a normal login screen — degraded but not broken, because at this point
there are no user accounts so the only option is the wizard's "create
your account" path.

`/var/lib/AccountsService/users/*` are also wiped because that's where
the display manager caches per-user avatars and last-session
information.

### 5c. Self-disable and reboot

```bash
systemctl disable oem-powerwash-finalize.service
rm -f /var/lib/oem-setup/powerwash.flag
sync
systemctl reboot
```

The unit disables itself so it never runs again until the next manual
arm step. The flag is removed so even if a future user re-enables the
unit by accident, the `ConditionPathExists=` short-circuits and
nothing happens.

The final reboot is for cleanliness — `oem-config-prepare` made
changes that take effect at the *next* `multi-user.target` start, and
the buyer's experience is best if those happen on a fresh boot rather
than mid-shutdown.

---

## What is guaranteed to survive a Powerwash

Because everything in this toolkit writes *system-level* files (under
`/etc/`, `/usr/`, `/var/`, never inside `$HOME`), all of the following
are still in place when the wizard appears:

- Every package the toolkit installed (Chrome, Zoom, VLC,
  papirus-icon-theme, …).
- Audio quirks and keyboard map from the hardware-fix step.
- GRUB / initramfs kernel parameters from the hardware-fix step.
- The Mint-Y-Aqua GTK theme (shipped by `mint-themes`) and
  `papirus-icon-theme` under `/usr/share`.
- The wallpaper file at `/usr/share/backgrounds/oem-setup/malta.jpg`.
- The 11 web-app `.desktop` entries and their icons.
- `/usr/local/bin/oem-first-run.sh`, which builds the panel-2 dock
  with eleven launchers on each new user's first XFCE login.
- The `/etc/skel` tree, so the buyer's freshly-created account gets
  the per-user defaults (xsettings.xml selecting Mint-Y-Aqua and
  Papirus, the autostart entries that trigger `oem-first-run.sh` and
  `touchegg --client`) on first login.
- The Powerwash tool itself.

## What does **not** survive

- Every regular user account and its home directory.
- Anything any user installed inside their home (e.g. flatpaks
  installed `--user`, Python venvs, manual app downloads).
- Display-manager caches under `/var/lib/AccountsService/users/`.

## What is intentionally not deleted

- System-wide installations made after the toolkit (e.g. a buyer who
  did `sudo apt install foo` keeps `foo`).
- The Google Chrome apt repository file. The buyer probably *wants*
  Chrome to keep updating.
- Toolkit backups under `/var/lib/oem-setup/backups/`. They cost
  almost nothing and let `step_uninstall` work for a future technician
  if the machine ever comes back.

---

## Debugging a misbehaving Powerwash

```bash
# Is the flag set?
ls -l /var/lib/oem-setup/powerwash.flag

# Is the unit enabled?
systemctl is-enabled oem-powerwash-finalize.service

# Why didn't it run on boot?
journalctl -u oem-powerwash-finalize.service -b -1

# What did the finalize script log?
cat /var/log/oem-powerwash.log

# Is the polkit policy registered?
pkaction --action-id org.linuxoem.powerwash.arm

# Did the menu entry land?
cat /usr/share/applications/oem-powerwash.desktop
```

The two most common failure modes are:

1. **The menu entry is missing or the icon is the generic one.** Run
   `gtk-update-icon-cache -f -t /usr/share/icons/hicolor` and
   `update-desktop-database /usr/share/applications`. `step_powerwash`
   does both but a partial uninstall can leave a stale cache.
2. **The wizard doesn't appear after the second reboot.** Check
   `/var/log/oem-powerwash.log` for an `oem-config-prepare` error.
   Usually this means `oem-config-gtk` is missing — re-run menu
   option 14 to reinstall it.
