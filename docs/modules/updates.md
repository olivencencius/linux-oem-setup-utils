# `modules/updates.sh`

## Purpose

Brings the base system up to date and installs the toolkit's universal
prerequisites (base tools, memory compression, power management). After
this step, the rest of the pipeline can assume a fresh apt cache and a
baseline set of utilities. Multimedia codecs are left to the OS
installer / image (not installed here).

## Function exported

`step_updates`

## Inputs

None.

## Outputs (filesystem & package state)

- `apt-get update` — refreshes the apt cache.
- `DEBIAN_FRONTEND=noninteractive apt-get upgrade -y` — upgrades every
  package on the system. `noninteractive` prevents `dpkg` from
  prompting about modified config files; the OEM workflow can't pause
  for that.
- Installs:
  - `git`, `wget`, `curl` — used by later modules to fetch source.
  - `xinput` — used by `step_touchpad` to apply natural scrolling to
    the live oem session.
  - `zram-tools` — ZRAM swap on compressed RAM, prevents stuttering
    on 4 GB eMMC Chromebooks.
  - `tlp` — battery management; enables and starts `tlp.service`.
  - (Note: `gimp` is now optional — see `step_gimp` menu option 14, not included in base updates)
- Exports `OEM_APT_FRESH=1` so other modules' `ensure_apt_fresh` calls
  short-circuit.

## Walkthrough

```bash
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
export OEM_APT_FRESH=1

apt-get install -y git wget curl xinput
apt-get install -y zram-tools tlp
systemctl enable --now tlp.service
```

Two logical sub-steps in two `apt-get install` calls plus the TLP
service enable.

## Notes

- `OEM_APT_FRESH` is **exported**, not just set, because module
  functions run in subshells under certain control structures and need
  to see it.
- `tlp.service` is `--now` enabled so power management kicks in
  immediately during QA (a Chromebook on battery in a workshop without
  TLP can chew through 5–10% of charge in an hour just idling).

## Idempotency

Fully idempotent:

- `apt-get update` always succeeds.
- `apt-get upgrade` is a no-op if everything is already current.
- `apt-get install -y <pkg>` is a no-op for already-installed packages.
- `systemctl enable --now tlp.service` is a no-op if already enabled
  and running.

## Uninstall counterpart

`step_uninstall` purges `tlp`, `zram-tools`, `imwheel` (legacy — no
longer installed by this module, but the purge is kept as a courtesy for
systems that ran an earlier revision of the toolkit). The other base tools
(`git`, `wget`, `curl`, `xinput`) are intentionally left in place.

If `step_gimp` was run (optional menu option 14), `step_uninstall` also
purges `gimp` (sub-step 2).

`OEM_APT_FRESH` is a per-process variable and is naturally cleared
when `setup.sh` exits.
