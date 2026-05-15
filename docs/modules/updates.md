# `modules/updates.sh`

## Purpose

Brings the base system up to date and installs the toolkit's universal
prerequisites (codecs, base tools, memory compression, power
management). After this step, the rest of the pipeline can assume a
fresh apt cache and a baseline set of utilities.

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
  - `mint-meta-codecs` — non-free media codecs (h.264, AAC, etc.).
  - `git`, `wget`, `curl` — used by later modules to fetch source.
  - `xinput` — used by `step_touchpad` to apply natural scrolling to
    the live oem session.
  - `gimp` — image editor; bundled into the base tools rather than
    `step_apps` because it's a general-purpose productivity tool.
  - `imwheel` — scroll-speed multiplier; installed here so the
    `step_touchpad` module doesn't need its own `apt-get install`.
  - `zram-tools` — ZRAM swap on compressed RAM, prevents stuttering
    on 4 GB eMMC Chromebooks.
  - `tlp` — battery management; enables and starts `tlp.service`.
- Exports `OEM_APT_FRESH=1` so other modules' `ensure_apt_fresh` calls
  short-circuit.

## Walkthrough

```bash
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
export OEM_APT_FRESH=1

apt-get install -y mint-meta-codecs git wget curl xinput gimp imwheel
apt-get install -y zram-tools tlp
systemctl enable --now tlp.service
```

Three logical sub-steps in two `apt-get install` calls plus the TLP
service enable. The split lets the technician read the log and see
*"base tools done"* before the larger ZRAM/TLP installation begins.

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

`step_uninstall` purges `tlp`, `zram-tools`, `mint-meta-codecs`,
`imwheel`, and `gimp` (sub-step 2). The other base tools
(`git`, `wget`, `curl`, `xinput`) are intentionally left in place
because they are routinely needed for general Linux administration.

`OEM_APT_FRESH` is a per-process variable and is naturally cleared
when `setup.sh` exits.
