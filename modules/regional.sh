#!/bin/bash
# ==============================================================================
#   Module:    regional.sh
#   Purpose:   step_regional — language packs for Polish deployments, system
#              locale (`LANG`). Does not touch keyboard layout or timezone;
#              those are configured during Xubuntu installer / OEM flow.
#   Reads:     helpers: ensure_apt_fresh
#   Writes:    apt: language-pack-pl, language-pack-gnome-pl,
#                   language-pack-en, language-pack-gnome-en, locales
#              /etc/locale.gen                    (via locale-gen)
#              /etc/default/locale                (via localectl)
#   Step fns:  step_regional
#   Docs:      docs/modules/regional.md
#   Uninstall: step_uninstall purges language packs (sub-step 2), may still
#              restore keyboard from a legacy snapshot (sub-step 11),
#              resets locale to en_US.UTF-8 and timezone to UTC,
#              clears STATE_DIR (sub-step 14).
# ==============================================================================

step_regional() {
    oem_tty_say "--> Configuring regional settings (language packs, locale)…"
    ensure_apt_fresh
    oem_run_log env DEBIAN_FRONTEND=noninteractive apt-get install -y language-pack-pl language-pack-gnome-pl \
                       language-pack-en language-pack-gnome-en \
                       locales

    # Belt-and-braces: language-pack-pl normally enables pl_PL.UTF-8 in
    # /etc/locale.gen, but on a fresh OEM image it's not always rebuilt
    # until the next boot. Generate explicitly so localectl can switch.
    oem_tty_say "--> Running locale-gen and localectl…"
    oem_run_log locale-gen pl_PL.UTF-8 en_US.UTF-8 || true

    oem_run_log localectl set-locale LANG=pl_PL.UTF-8
}
