# `modules/regional.sh`

## Purpose

Two related responsibilities:

1. **`prompt_keyboard`** — the one human interaction the full
   pipeline needs, asked up-front so the rest can run unattended.
2. **`step_regional`** — installs language packs, generates locales,
   applies locale (`LANG`), timezone, and the chosen `XKBLAYOUT` for
   the physical keyboard.

## Functions exported

- `prompt_keyboard` — called by `setup.sh` at the start of
  `run_full_pipeline`, and (defensively) by `step_regional` itself
  if `$KB_LAYOUT` isn't set.
- `step_regional` — called by `run_step` as part of the pipeline,
  and by `do_step` when menu option 13 is picked.

## Inputs

- `$STATE_DIR/kb_layout` (persisted choice from a previous run).
- `ensure_apt_fresh` and `backup_once` (helpers from `setup.sh`).
- `/dev/tty` (the keyboard prompt reads from it).

## Outputs

Installed packages:

- `language-pack-pl`, `language-pack-gnome-pl`
- `language-pack-en`, `language-pack-gnome-en`
- `locales`

System files:

- `$STATE_DIR/kb_layout` — written by `prompt_keyboard` so a resumed
  pipeline doesn't re-ask.
- `/etc/default/keyboard` — `XKBLAYOUT="$KB_LAYOUT"` and
  `XKBVARIANT=""` (any non-empty variant is cleared to avoid carrying
  forward a wrong one from the Mint installer).
- `/etc/locale.gen` (touched by `locale-gen`) — `pl_PL.UTF-8` and
  `en_US.UTF-8` ensured enabled.
- `/etc/default/locale` (via `localectl`) — `LANG=pl_PL.UTF-8`.
- `/etc/timezone` and `/etc/localtime` (via `timedatectl`) — set to
  `Europe/Warsaw`.

Backup taken:

- `/etc/default/keyboard`.

## Walkthrough

### `prompt_keyboard`

```bash
prompt_keyboard() {
    if [ -f "$STATE_DIR/kb_layout" ]; then
        KB_LAYOUT=$(cat "$STATE_DIR/kb_layout")
        export KB_LAYOUT
        return
    fi

    # ... print menu ...
    read -p "Enter number [1-5]: " kb_choice < /dev/tty

    case $kb_choice in
        1) KB_LAYOUT="us" ;;
        2) KB_LAYOUT="gb" ;;
        3) KB_LAYOUT="de" ;;
        4) KB_LAYOUT="se" ;;
        5) KB_LAYOUT="pl" ;;
        *) KB_LAYOUT="us" ;;
    esac
    export KB_LAYOUT
    echo "$KB_LAYOUT" > "$STATE_DIR/kb_layout"
}
```

- **Persistence**: the chosen layout is written to
  `/var/lib/oem-setup/state/kb_layout`. A resumed pipeline reads it
  and skips the prompt. To re-prompt: delete that file (or `rm -rf`
  the whole state dir).
- **`< /dev/tty`** is required because under `curl … | sudo bash`
  stdin is the curl pipe, not the terminal.
- **Invalid input falls back to `us`** rather than re-prompting in
  a loop. The technician sees a clear `[!] Invalid input — defaulting`
  message and can re-run option 13 to change it if needed. This
  prevents an infinite re-prompt loop in scripted setups.
- Five layouts are offered because they cover ~99% of OEM machines
  for this seller's market (US, UK, DE, SE, PL).

### `step_regional`

```bash
step_regional() {
    if [ -z "${KB_LAYOUT:-}" ]; then
        prompt_keyboard
    fi

    ensure_apt_fresh
    apt-get install -y language-pack-pl language-pack-gnome-pl \
                       language-pack-en language-pack-gnome-en \
                       locales

    locale-gen pl_PL.UTF-8 en_US.UTF-8 || true

    localectl set-locale LANG=pl_PL.UTF-8
    timedatectl set-timezone Europe/Warsaw

    backup_once /etc/default/keyboard
    sed -i "s/XKBLAYOUT=.*/XKBLAYOUT=\"$KB_LAYOUT\"/g" /etc/default/keyboard
    sed -i 's/^XKBVARIANT=.*/XKBVARIANT=""/g'          /etc/default/keyboard
    setupcon
}
```

Five sub-steps:

1. **Defensive `prompt_keyboard`** if `$KB_LAYOUT` isn't set. This
   matters when menu option 13 is picked stand-alone (no preceding
   `prompt_keyboard` from `run_full_pipeline`).
2. **Install language packs** for Polish (the deployment target) and
   English (the buyer's likely fallback). `language-pack-gnome-*`
   pulls in GNOME app translations even though XFCE is the desktop —
   many apps in Mint are GNOME-derived.
3. **`locale-gen pl_PL.UTF-8 en_US.UTF-8 || true`** — belt and
   braces. `language-pack-pl` normally enables `pl_PL.UTF-8` in
   `/etc/locale.gen`, but on a fresh OEM image the locale isn't
   always rebuilt until the next boot. Calling `locale-gen` directly
   guarantees `localectl` can switch immediately. `|| true` covers
   the case where the locale is already compiled.
4. **`localectl` + `timedatectl`** apply locale and timezone.
5. **Keyboard layout** via two `sed` operations on
   `/etc/default/keyboard` followed by `setupcon`. The `XKBVARIANT=""`
   wipe is critical: if the Mint installer left a variant set (e.g.
   `XKBVARIANT="winkeys"` for a non-existent winkeys variant), `setupcon`
   would fail to apply the layout.

## Notes

- **Why split prompt and step?** The full pipeline takes ~20 minutes.
  Asking the layout at the *end* would mean the technician has to
  babysit. Asking up front means one answer, then walk away.
- **`KB_LAYOUT` is exported** so a child `step_regional` (called
  inside `do_step`'s subshell or via menu option 13) can read it.
- **Timezone is hard-coded** to `Europe/Warsaw`. The buyer changes it
  in the OEM welcome wizard if they want; this is just the default.
- **`setupcon`** is the Ubuntu/Mint command that re-applies the
  `/etc/default/keyboard` config to the running session's console and
  X server. Without it the file change wouldn't take effect until the
  next boot.

## Idempotency

Fully idempotent:

- `prompt_keyboard` short-circuits on the persisted state file.
- `apt-get install` is a no-op for installed packages.
- `locale-gen` for an already-generated locale is a no-op.
- `localectl set-locale` and `timedatectl set-timezone` are
  value-set commands; re-applying the same value is a no-op.
- The `sed` replacements idempotently overwrite the lines.

## Uninstall counterpart

`step_uninstall`:

- `apt purge` language packs (sub-step 2).
- `restore_or_skip /etc/default/keyboard` (sub-step 11). If no backup,
  sed `XKBLAYOUT="us"`.
- `setupcon` to apply the reverted keyboard.
- `localectl set-locale LANG=en_US.UTF-8`.
- `timedatectl set-timezone UTC`.
- `rm $STATE_DIR/kb_layout` (implicit — sub-step 14 nukes the entire
  `state/` dir).
