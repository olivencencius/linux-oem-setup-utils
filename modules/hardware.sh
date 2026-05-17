#!/bin/bash
# ==============================================================================
#   Module:    hardware.sh
#   Purpose:   Apply Chromebook-specific hardware fixes: audio quirks
#              (chromebook-linux-audio), top-row keyboard map
#              (cros-keyboard-map), CELES HPET clock-source workaround,
#              Tiger/AlderLake Type-C initramfs modules.
#   Reads:     /sys/class/dmi/id/product_name, dmesg, lscpu
#              REPO_DIR, /dev/tty
#              helpers: backup_once
#   Writes:    apt (via upstream): keyd and audio dependencies
#              /etc/default/grub               (CELES: clocksource=hpet hpet=force)
#              /etc/initramfs-tools/modules    (Tiger/AlderLake: cros-ec-typec,
#                                               intel-pmc-mux)
#              /var/lib/oem-setup/backups/{grub,modules}
#              + whatever the two upstream installers write under
#                /usr/share/alsa, /etc/udev/rules.d, /etc/keyd, ...
#   Step fn:   step_hardware_fixes
#   Docs:      docs/modules/hardware.md
#   Uninstall: step_uninstall (sub-steps 5, 6) — best-effort audio quirks
#              cleanup, restore grub and initramfs-tools/modules from backups
#              or sed-remove our lines, purge keyd.
#
#   NOTE — INTERACTIVE: audio + keyboard installers use oem_run_interactive (stdio
#   on fd 3 / real TTY). That UI is not copied into /var/log/oem-setup.log — only
#   START/END markers; watch the terminal during these two steps.
# ==============================================================================

step_hardware_fixes() {
    oem_tty_say \
        "--> Chromebook audio and keyboard optimisations..." \
        "    [i] The upstream installers below MAY ASK QUESTIONS." \
        "        Answer them at the prompt — they pick the correct config" \
        "        for your specific Chromebook board." \
        ""

    cd /tmp

    oem_tty_say "--> Cloning chromebook-linux-audio (needs network)…"
    rm -rf /tmp/chromebook-linux-audio
    oem_run_log git clone --depth 1 --progress https://github.com/WeirdTreeThing/chromebook-linux-audio.git
    oem_tty_say "--> Running audio installer (interactive — answer any prompts on THIS terminal)…"
    ( cd /tmp/chromebook-linux-audio && oem_run_interactive ./setup-audio )

    oem_tty_say "--> Cloning cros-keyboard-map (needs network)…"
    rm -rf /tmp/cros-keyboard-map
    oem_run_log git clone --depth 1 --progress https://github.com/WeirdTreeThing/cros-keyboard-map.git
    oem_tty_say "--> Running keyboard-map installer (interactive — answer any prompts on THIS terminal)…"
    ( cd /tmp/cros-keyboard-map && oem_run_interactive ./install.sh )

    oem_tty_say "--> Analysing motherboard for specialised patches..."

    # CELES (Samsung) — freeze mitigation via HPET clock source.
    # DMI is the authoritative source for the board name; dmesg is a noisy
    # fallback that can fail if the kernel ringbuffer was truncated.
    local board=""
    if [ -r /sys/class/dmi/id/product_name ]; then
        board=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
    fi
    if echo "$board" | grep -qi "celes" || dmesg | grep -qi "celes"; then
        oem_tty_say "    [!] CELES board detected (product_name='$board') — injecting HPET kernel params..."
        if ! grep -q "clocksource=hpet" /etc/default/grub; then
            backup_once /etc/default/grub
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="clocksource=hpet hpet=force /' \
                /etc/default/grub
            oem_tty_say "--> update-grub (HPET change)…"
            oem_run_log update-grub
        else
            oem_tty_say "    [i] HPET params already present in /etc/default/grub — leaving alone."
        fi
    else
        oem_tty_say "    [i] CELES not detected — skipping HPET fix."
    fi

    # TigerLake / AlderLake — USB-C module fix
    if lscpu | grep -qiE "tiger|alder"; then
        oem_tty_say "    [!] Tiger/AlderLake CPU detected — forcing Type-C driver stack..."
        local changed=0
        if ! grep -qx 'cros-ec-typec' /etc/initramfs-tools/modules; then
            backup_once /etc/initramfs-tools/modules
            echo "cros-ec-typec"   >> /etc/initramfs-tools/modules
            changed=1
        fi
        if ! grep -qx 'intel-pmc-mux' /etc/initramfs-tools/modules; then
            backup_once /etc/initramfs-tools/modules
            echo "intel-pmc-mux"  >> /etc/initramfs-tools/modules
            changed=1
        fi
        if [ "$changed" = "1" ]; then
            oem_tty_say "--> update-initramfs (Type-C modules — can take a few minutes)…"
            oem_run_log update-initramfs -u -k all
        else
            oem_tty_say "    [i] Type-C modules already in initramfs — leaving alone."
        fi
    else
        oem_tty_say "    [i] Not a Tiger/AlderLake CPU — skipping Type-C fix."
    fi
}
