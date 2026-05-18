# `modules/terminal.sh`

## Purpose

Disables bash's **bracketed paste mode** system-wide so pasting a
multi-line block into a terminal does not produce `0~…1~` garbage at
the start and end.

## Function exported

`step_terminal`

## Inputs

- `backup_once` (helper from `setup.sh`).

## Outputs

- One line appended to `/etc/inputrc` (system-wide readline default):

  ```
  set enable-bracketed-paste off
  ```

- The same line appended to `/etc/skel/.inputrc` for every future
  user account.

- The same line appended to **`~/.inputrc`** for every **existing**
  login user (UID 1000–65533 with a home directory) that does not
  already have it — so accounts created **before** this step (e.g.
  children’s users) still get the fix.

Backup taken:

- `/etc/inputrc` (if it existed before this step ran).

## Walkthrough

```bash
if ! grep -qxF 'set enable-bracketed-paste off' /etc/inputrc; then
    backup_once /etc/inputrc
    echo "set enable-bracketed-paste off" >> /etc/inputrc
fi

mkdir -p /etc/skel
if ! grep -qxF 'set enable-bracketed-paste off' /etc/skel/.inputrc 2>/dev/null; then
    echo "set enable-bracketed-paste off" >> /etc/skel/.inputrc
fi

_oem_sync_inputrc_bracketed_paste_all_users
```

`grep -qxF` (-x exact line, -F fixed string) protects against
appending duplicate lines on a re-run.

`/etc/skel/.inputrc` may not exist on a fresh Xubuntu install. The
`grep … 2>/dev/null` suppresses the error so the `if !` simply
evaluates true, and we append the line, creating the file if needed.

## Notes

- The bracketed-paste mode is a `readline` (= bash interactive)
  feature; this only affects bash and shells that inherit bash's
  readline config. zsh and fish have their own equivalents (zsh
  defaults to off; fish doesn't use bracketed paste).
- Why disable it instead of teaching users how to handle it? On
  Chromebook keyboards the function keys are remapped and the
  terminal copy-paste workflow has to be bullet-proof for a
  non-technical buyer who got the device second-hand.

## Idempotency

Fully idempotent thanks to the `grep -qxF` guards.

## Uninstall counterpart

`step_uninstall` (sub-step 10):

- `restore_or_skip /etc/inputrc` — if a backup exists, restore it;
  otherwise sed-remove only the one line this module appended.
- Same treatment for `/etc/skel/.inputrc`, with the additional cleanup
  of removing the file entirely if empty after the sed.
