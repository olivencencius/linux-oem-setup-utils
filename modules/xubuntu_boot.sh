#!/bin/bash
# ==============================================================================
#   Module:    xubuntu_boot.sh
#   Purpose:   Machine-wide boot polish for Xubuntu LTS resale images: systemd
#              tuning (ModemManager, NM-wait-online, snapd), Plymouth + GRUB
#              silent-boot parameters, and extra kernel tokens that reduce TTY1
#              getty noise before LightDM. Part of the default pipeline (after
#              hardware_fixes) and re-runnable via menu option 2.
#
#              Does not mask systemd-udev-settle (try without first; measure with
#              systemd-analyze blame before masking manually).
#
#   Reads:     /etc/default/grub, /etc/grub.d/10_linux — helpers: backup_once,
#              ensure_apt_fresh
#   Writes:    systemd unit symlinks; plymouth packages; /etc/default/grub +
#              update-grub when changed
#   Step fn:   step_xubuntu_boot
#   Docs:      docs/modules/xubuntu_boot.md
#   Uninstall: step_uninstall restores units + strips GRUB tokens (fallback sed)
# ==============================================================================

step_xubuntu_boot() {
    oem_tty_say "--> Xubuntu LTS boot optimisations (systemd + GRUB + Plymouth)…"

    ensure_apt_fresh

    # Plymouth splash stack — reduces raw TTY visibility before the DM handoff.
    local ply_pkgs=(plymouth)
    local _p
    for _p in plymouth-theme-xubuntu-logo plymouth-theme-xubuntu-text; do
        if apt-cache show "$_p" &>/dev/null; then
            ply_pkgs+=("$_p")
        fi
    done
    oem_tty_say "    [.] Installing Plymouth packages: ${ply_pkgs[*]}…"
    oem_run_log env DEBIAN_FRONTEND=noninteractive apt-get install -y "${ply_pkgs[@]}" || true

    if command -v plymouth-set-default-theme &>/dev/null; then
        if plymouth-set-default-theme -l 2>/dev/null | grep -qx 'xubuntu-logo'; then
            oem_run_log plymouth-set-default-theme xubuntu-logo 2>/dev/null || true
            oem_tty_say "    [+] Plymouth theme set to xubuntu-logo."
        elif plymouth-set-default-theme -l 2>/dev/null | grep -qx 'xubuntu-text'; then
            oem_run_log plymouth-set-default-theme xubuntu-text 2>/dev/null || true
            oem_tty_say "    [+] Plymouth theme set to xubuntu-text."
        fi
    fi

    if systemctl list-unit-files 2>/dev/null | grep -q '^ModemManager\.service'; then
        systemctl disable --now ModemManager.service 2>/dev/null || true
        oem_tty_say "    [+] Disabled ModemManager.service."
    else
        oem_tty_say "    [i] ModemManager.service not installed — skipping."
    fi

    if systemctl list-unit-files 2>/dev/null | grep -q '^NetworkManager-wait-online\.service'; then
        systemctl mask --now NetworkManager-wait-online.service 2>/dev/null || true
        oem_tty_say "    [+] Masked NetworkManager-wait-online.service."
    else
        oem_tty_say "    [i] NetworkManager-wait-online.service not found — skipping."
    fi

    local snap_any=0
    if systemctl list-unit-files 2>/dev/null | grep -q '^snapd\.socket'; then
        systemctl disable --now snapd.socket 2>/dev/null || true
        snap_any=1
    fi
    if systemctl list-unit-files 2>/dev/null | grep -q '^snapd\.service'; then
        systemctl disable --now snapd.service 2>/dev/null || true
        snap_any=1
    fi
    if [ "$snap_any" = "1" ]; then
        oem_tty_say "    [+] Disabled snapd.socket / snapd.service."
    else
        oem_tty_say "    [i] snapd units not found — skipping."
    fi

    local grub_changed=0
    if [ ! -f /etc/default/grub ]; then
        oem_tty_say "    [!] /etc/default/grub missing — GRUB tweaks skipped."
        oem_tty_say "    [!] Reboot to apply systemd changes; GRUB was not modified."
        return 0
    fi

    local tok
    for tok in quiet splash loglevel=3 vt.global_cursor_default=0 \
               systemd.show_status=no rd.systemd.show_status=no; do
        if grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | grep -Fq "$tok"; then
            continue
        fi
        backup_once /etc/default/grub
        sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/s/\"\$/ ${tok}\"/" /etc/default/grub
        grub_changed=1
    done

    # Stock Ubuntu GRUB injects vt.handoff via $vt_handoff in 10_linux — avoid
    # duplicating vt.handoff= on GRUB_CMDLINE_LINUX_DEFAULT.
    local use_vt_handoff=1
    if [ -f /etc/grub.d/10_linux ] && grep -q 'vt_handoff' /etc/grub.d/10_linux; then
        use_vt_handoff=0
    fi
    if [ "$use_vt_handoff" = "1" ]; then
        tok="vt.handoff=7"
        if ! grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | grep -Fq "$tok"; then
            backup_once /etc/default/grub
            sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/s/\"\$/ ${tok}\"/" /etc/default/grub
            grub_changed=1
            oem_tty_say "    [+] Appended vt.handoff=7 (no vt_handoff in /etc/grub.d/10_linux)."
        fi
    else
        oem_tty_say "    [i] GRUB 10_linux provides vt_handoff — not adding vt.handoff=7 to DEFAULT."
    fi

    if [ "$grub_changed" = "1" ]; then
        oem_tty_say "    [+] Appended silent-boot / systemd GRUB parameters to GRUB_CMDLINE_LINUX_DEFAULT."
        if command -v update-grub &>/dev/null; then
            oem_tty_say "--> Running update-grub…"
            oem_run_log update-grub
        else
            oem_tty_say "    [!] update-grub not found — regenerate GRUB manually."
        fi
    else
        oem_tty_say "    [i] Boot-related GRUB parameters already present — leaving alone."
    fi

    oem_tty_say "" "    [i] Reboot to apply GRUB, Plymouth, and systemd boot behaviour."
    oem_tty_say "    [i] Full uninstall (menu 15) reverses these changes."
}
