# `modules/flathub.sh`

## Purpose

Adds the [Flathub](https://flathub.org) flatpak remote so the **buyer**
can install flatpak apps later without first having to add the remote
themselves. The toolkit installs **no flatpak apps itself**.

## Function exported

`step_flathub`

## Inputs

None.

## Outputs

- A Flathub remote registered in flatpak's system config.
- Any auto-updated metadata for already-installed flatpaks (in
  practice: none, on a fresh OEM machine).

## Walkthrough

```bash
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak update -y || true
```

`--if-not-exists` makes the step idempotent. `flatpak update -y` is
allowed to fail (`|| true`) because on a brand-new install there are
no apps to update; some Mint versions return non-zero from
`flatpak update` when the local store is empty.

## Notes

- **Why not just install flatpaks?** Native apt is preferred throughout
  this toolkit to save the ~1.5 GB `org.gnome.Platform` /
  `org.freedesktop.Platform` runtime that the first flatpak install
  would pull onto a 4 GB eMMC. The Flathub remote is added so the buyer
  has frictionless access to flatpaks if they want them; the cost of
  the remote itself is essentially zero (a few dozen KB of metadata).
- `flatpak` itself is part of the Mint OEM image; we don't apt-install
  it here.

## Idempotency

Fully idempotent — `--if-not-exists` short-circuits if the remote is
already registered.

## Uninstall counterpart

`step_uninstall` runs `flatpak remote-delete --force flathub` (sub-step
3) if `flatpak` is available.
