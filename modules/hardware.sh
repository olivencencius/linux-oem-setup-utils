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
#   NOTE — INTERACTIVE: the audio and keyboard installers may ask the
#   technician questions. Their stdin is wired to /dev/tty so prompts work
#   even under `curl … | sudo bash`. WATCH THE SCREEN.
# ==============================================================================

step_hardware_fixes() {
    echo "--> Chromebook audio and keyboard optimisations..."
    echo "    [i] The upstream installers below MAY ASK QUESTIONS."
    echo "        Answer them at the prompt — they pick the correct config"
    echo "        for your specific Chromebook board."
    echo ""

    cd /tmp

    rm -rf /tmp/chromebook-linux-audio
    git clone --depth 1 https://github.com/WeirdTreeThing/chromebook-linux-audio.git
    ( cd /tmp/chromebook-linux-audio && ./setup-audio < /dev/tty )

    rm -rf /tmp/cros-keyboard-map
    git clone --depth 1 https://github.com/WeirdTreeThing/cros-keyboard-map.git
    ( cd /tmp/cros-keyboard-map && ./install.sh < /dev/tty )

    echo "--> Analysing motherboard for specialised patches..."

    # CELES (Samsung) — freeze mitigation via HPET clock source.
    # DMI is the authoritative source for the board name; dmesg is a noisy
    # fallback that can fail if the kernel ringbuffer was truncated.
    local board=""
    if [ -r /sys/class/dmi/id/product_name ]; then
        board=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
    fi
    if echo "$board" | grep -qi "celes" || dmesg | grep -qi "celes"; then
        echo "    [!] CELES board detected (product_name='$board') — injecting HPET kernel params..."
        if ! grep -q "clocksource=hpet" /etc/default/grub; then
            backup_once /etc/default/grub
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="clocksource=hpet hpet=force /' \
                /etc/default/grub
            update-grub
        else
            echo "    [i] HPET params already present in /etc/default/grub — leaving alone."
        fi
    else
        echo "    [i] CELES not detected — skipping HPET fix."
    fi

    # TigerLake / AlderLake — USB-C module fix
    if lscpu | grep -qiE "tiger|alder"; then
        echo "    [!] Tiger/AlderLake CPU detected — forcing Type-C driver stack..."
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
            update-initramfs -u -k all
        else
            echo "    [i] Type-C modules already in initramfs — leaving alone."
        fi
    else
        echo "    [i] Not a Tiger/AlderLake CPU — skipping Type-C fix."
    fi
}
