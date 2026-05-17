#!/bin/bash
# ==============================================================================
#   Module:    uninstall.sh
#   Purpose:   Best-effort reversal of every change this toolkit makes.
#              Restores from /var/lib/oem-setup/backups/ where possible;
#              falls back to sed-based line removal where no backup exists.
#   Reads:     SUDO_USER (optional), fd 3 (YES confirmation — TTY from setup.sh)
#              /var/lib/oem-setup/backups/{grub,modules,inputrc,keyboard}
#   Writes:    Reverts every system-level change the toolkit makes —
#              15 sub-steps detailed in docs/uninstall.md.
#              /var/lib/oem-setup/backups/ (kept for repeat uninstalls).
#   Step fn:   step_uninstall
#   Helpers:   note, restore_or_skip (file-scope)
#   Docs:      docs/modules/uninstall.md   (this module)
#              docs/uninstall.md            (cross-cutting reverted-items map)
#
#   NOTE: Invoked DIRECTLY from the menu (option 15), not via do_step.
#   Owns its own YES confirmation. Never writes an uninstall.done marker —
#   re-runs always proceed (which is what you want for idempotent cleanup).
# ==============================================================================

BACKUP_DIR="/var/lib/oem-setup/backups"

# Tracks "best-effort" residual notes for the final summary
UNINSTALL_NOTES=()
note() { UNINSTALL_NOTES+=("$1"); }

# Restore a file from BACKUP_DIR if present; otherwise return non-zero so the
# caller can fall back to a sed-based line removal.
restore_or_skip() {
    local target="$1"
    local backup="$BACKUP_DIR/$(basename "$target")"
    if [ -e "$backup" ]; then
        cp -a "$backup" "$target"
        oem_tty_say "    [+] Restored $target from backup."
        return 0
    fi
    return 1
}

step_uninstall() {
    oem_tty_say \
        "" \
        "=========================================" \
        "         UNDO / FULL UNINSTALL           " \
        "=========================================" \
        "This will remove every package and config change this toolkit made:" \
        "  - Purge: Chrome, Zoom, VLC, GIMP, TLP, ZRAM tools," \
        "          imwheel (legacy), plank, touchegg, xfdashboard, keyd," \
        "          language packs," \
        "          games (SuperTuxKart, Aisleriot, Quadrapassel)" \
        "  - Remove Google Chrome apt repository and signing key" \
        "  - Revert optional Xubuntu boot optimisations (systemd + GRUB silent-boot tokens)" \
        "  - Revert /etc/default/grub, /etc/initramfs-tools/modules," \
        "          /etc/inputrc, /etc/default/keyboard" \
        "  - Delete web-app .desktop entries, icons, wallpaper, oem-first-run" \
        "  - Clean /etc/skel and every user's home of toolkit artefacts" \
        "  - Reset locale to en_US.UTF-8 and timezone to UTC" \
        "  - Clear the oem-setup state markers and saved keyboard layout" \
        "========================================="
    printf "Type 'YES' (uppercase) to proceed, anything else to abort: " >&3
    read -r confirm < /dev/tty || true
    if [ "$confirm" != "YES" ]; then
        oem_tty_say "Uninstall aborted."
        return 0
    fi
    oem_tty_say ""

    # -------------------------------------------------------------------------
    # 1. Stop running services & user helpers BEFORE purging their packages
    # -------------------------------------------------------------------------
    oem_tty_say "--> Stopping services…"
    for svc in tlp touchegg keyd; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
            systemctl disable --now "$svc" 2>/dev/null || true
        fi
    done

    if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null; then
        # Legacy: imwheel was removed from the toolkit; kill it on old installs.
        sudo -u "$SUDO_USER" pkill -x imwheel              2>/dev/null || true
        sudo -u "$SUDO_USER" pkill -f 'touchegg --client'  2>/dev/null || true
        # Plank is the active ChromeOS-style dock — stop it before purging so
        # the running process does not hold open dbus / file handles.
        sudo -u "$SUDO_USER" pkill -x plank                2>/dev/null || true
        sudo -u "$SUDO_USER" pkill -x xfdashboard          2>/dev/null || true
    fi

    # -------------------------------------------------------------------------
    # 2. Apt purge — full scope (every package this toolkit installs)
    # -------------------------------------------------------------------------
    oem_tty_say "--> Purging installed packages (apt may take several minutes)…"
    oem_run_log env DEBIAN_FRONTEND=noninteractive apt-get purge -y \
        google-chrome-stable \
        zoom \
        vlc \
        supertuxkart \
        aisleriot \
        quadrapassel \
        plank \
        gimp \
        imwheel \
        tlp \
        zram-tools \
        language-pack-pl \
        language-pack-gnome-pl \
        language-pack-en \
        language-pack-gnome-en \
        touchegg \
        xfdashboard \
        wmctrl \
        xdotool \
        keyd \
        || true

    oem_run_log env DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y 2>/dev/null || true
    oem_run_log env DEBIAN_FRONTEND=noninteractive apt-get autoclean -y          2>/dev/null || true

    # -------------------------------------------------------------------------
    # 2b. Remove the Google Chrome apt repository and signing key that the
    #     Chrome .deb installs in its postinst. apt purge of the package does
    #     not remove these, and a future `apt update` will keep talking to
    #     Google.
    # -------------------------------------------------------------------------
    oem_tty_say "--> Removing Google Chrome apt repository and signing key…"
    rm -f /etc/apt/sources.list.d/google-chrome.list \
          /etc/apt/sources.list.d/google.list \
          /etc/apt/trusted.gpg.d/google-chrome.gpg \
          /usr/share/keyrings/google-chrome.gpg
    oem_run_log env DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>/dev/null || true

    # -------------------------------------------------------------------------
    # 3. (Formerly Flathub — toolkit no longer adds flatpak remotes.)
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    # 4. Chromebook-linux-audio quirks (best-effort; upstream has no uninstaller)
    # -------------------------------------------------------------------------
    oem_tty_say "--> Cleaning chromebook-linux-audio quirks (best-effort)…"
    rm -rf  /usr/share/alsa/ucm2/codecs/cros-* \
            /usr/share/alsa/ucm2/cros-* \
            /usr/share/alsa/ucm2/conf.d/sof-*chrome* \
            2>/dev/null || true
    rm -f   /etc/udev/rules.d/99-cros-* \
            /etc/udev/rules.d/99-sof-*chrome* \
            /usr/lib/systemd/system/cros-* \
            2>/dev/null || true
    note "chromebook-linux-audio has no upstream uninstaller — board-specific PipeWire/ALSA quirks may still be present. A fresh OS install is the only fully-clean reset."

    # -------------------------------------------------------------------------
    # 5. Hardware-fix config: GRUB + initramfs-tools/modules
    # -------------------------------------------------------------------------
    oem_tty_say "--> Reverting /etc/default/grub…"
    if ! restore_or_skip /etc/default/grub; then
        if [ -f /etc/default/grub ]; then
            sed -i 's/clocksource=hpet hpet=force //g' /etc/default/grub
            sed -i -e 's/ vt\.global_cursor_default=0//g' \
                -e 's/ loglevel=3//g' \
                -e 's/ splash//g' \
                -e 's/ quiet//g' \
                /etc/default/grub
            sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/s/[[:space:]]\{2,\}/ /g' /etc/default/grub
            oem_tty_say "    [+] Removed toolkit kernel params from GRUB_CMDLINE_LINUX_DEFAULT."
        fi
    fi
    if command -v update-grub &>/dev/null; then
        oem_run_log update-grub 2>/dev/null || true
    fi

    oem_tty_say "--> Reverting optional Xubuntu boot systemd tweaks…"
    systemctl unmask NetworkManager-wait-online.service 2>/dev/null || true
    systemctl enable NetworkManager-wait-online.service 2>/dev/null || true
    systemctl enable ModemManager.service 2>/dev/null || true
    systemctl start ModemManager.service 2>/dev/null || true
    systemctl enable snapd.socket 2>/dev/null || true
    systemctl enable snapd.service 2>/dev/null || true
    oem_tty_say "    [+] Best-effort restore of ModemManager, NM-wait-online, snapd defaults."

    oem_tty_say "--> Reverting /etc/initramfs-tools/modules…"
    if ! restore_or_skip /etc/initramfs-tools/modules; then
        if [ -f /etc/initramfs-tools/modules ]; then
            sed -i -e '/^cros-ec-typec$/d' -e '/^intel-pmc-mux$/d' \
                /etc/initramfs-tools/modules
            oem_tty_say "    [+] Removed 'cros-ec-typec' / 'intel-pmc-mux' lines."
        fi
    fi
    if command -v update-initramfs &>/dev/null; then
        oem_run_log update-initramfs -u -k all 2>/dev/null || true
    fi

    # -------------------------------------------------------------------------
    # 6. Touchpad / gestures config
    # -------------------------------------------------------------------------
    oem_tty_say "--> Removing touchpad and gestures config…"
    rm -f /etc/X11/xorg.conf.d/40-chromebook-touchpad.conf
    rm -f /etc/touchegg/touchegg.conf
    rmdir --ignore-fail-on-non-empty /etc/touchegg 2>/dev/null || true

    # -------------------------------------------------------------------------
    # 7. Wallpaper / first-run script
    #    (no Plank dconf override to remove — we never wrote one)
    # -------------------------------------------------------------------------
    oem_tty_say "--> Removing wallpaper and first-run script…"
    rm -rf /usr/share/backgrounds/oem-setup
    rm -f  /usr/local/bin/oem-first-run.sh
    rm -f  /usr/share/applications/oem-workspace-overview.desktop

    # Legacy: clean up any dconf/Plank artefacts left by earlier toolkit revisions.
    rm -f /etc/xdg/autostart/plank.desktop
    rm -f /etc/dconf/db/local.d/00-plank
    if command -v dconf &>/dev/null; then
        dconf update 2>/dev/null || true
    fi

    # -------------------------------------------------------------------------
    # 8. Web-app shortcuts (.desktop + icons)
    # -------------------------------------------------------------------------
    oem_tty_say "--> Removing web-app shortcuts and icons…"
    local WEBAPP_NAMES=(
        Netflix PrimeVideo DisneyPlus HBOMax Spotify YouTube
        Gmail GoogleDocs GoogleSheets GoogleSlides GoogleDrive Gemini ChromeRemoteDesktop
    )
    local ICON_NAMES=(
        netflix primevideo disneyplus hbomax spotify youtube
        gmail googledocs googlesheets googleslides googledrive gemini chromeremotedesktop
    )
    for name in "${WEBAPP_NAMES[@]}"; do
        rm -f "/usr/share/applications/${name}.desktop"
    done
    for icon in "${ICON_NAMES[@]}"; do
        rm -f "/usr/share/icons/hicolor/scalable/apps/${icon}.svg"
    done
    if command -v gtk-update-icon-cache &>/dev/null; then
        gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
    fi

    # -------------------------------------------------------------------------
    # 9. Terminal — bracketed paste fix
    # -------------------------------------------------------------------------
    oem_tty_say "--> Reverting terminal paste fix…"
    if ! restore_or_skip /etc/inputrc; then
        if [ -f /etc/inputrc ]; then
            sed -i '/^set enable-bracketed-paste off$/d' /etc/inputrc
        fi
    fi
    if [ -f /etc/skel/.inputrc ]; then
        sed -i '/^set enable-bracketed-paste off$/d' /etc/skel/.inputrc
        [ ! -s /etc/skel/.inputrc ] && rm -f /etc/skel/.inputrc
    fi

    # -------------------------------------------------------------------------
    # 10. Regional — keyboard, locale, timezone
    # -------------------------------------------------------------------------
    oem_tty_say "--> Reverting regional settings…"
    if ! restore_or_skip /etc/default/keyboard; then
        if [ -f /etc/default/keyboard ]; then
            sed -i 's/XKBLAYOUT=".*"/XKBLAYOUT="us"/' /etc/default/keyboard
        fi
    fi
    if command -v setupcon &>/dev/null; then
        setupcon 2>/dev/null || true
    fi
    localectl   set-locale  LANG=en_US.UTF-8  2>/dev/null || true
    timedatectl set-timezone UTC              2>/dev/null || true

    # -------------------------------------------------------------------------
    # 11. /etc/skel cleanup — files this toolkit placed there
    # -------------------------------------------------------------------------
    oem_tty_say "--> Cleaning /etc/skel artefacts…"
    # Current artefacts
    rm -f  /etc/skel/.config/autostart/oem-first-run.desktop
    rm -f  /etc/skel/.config/autostart/touchegg-client.desktop
    rm -f  /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml
    # Legacy artefacts (imwheel, plank, gtk-4.0 symlinks from earlier revisions)
    rm -f  /etc/skel/.imwheelrc
    rm -f  /etc/skel/.config/autostart/imwheel.desktop
    rm -f  /etc/skel/.config/autostart/plank.desktop
    rm -rf /etc/skel/.config/plank
    rm -f  /etc/skel/.config/gtk-4.0/{assets,gtk.css,gtk-dark.css}
    rmdir --ignore-fail-on-non-empty -p \
        /etc/skel/.config/autostart \
        /etc/skel/.config/gtk-4.0 \
        /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml \
        2>/dev/null || true

    # Legacy: /root/.config/gtk-4.0 created by old ChromeOS theme install.
    rm -f /root/.config/gtk-4.0/{assets,gtk.css,gtk-dark.css}
    rmdir --ignore-fail-on-non-empty /root/.config/gtk-4.0 2>/dev/null || true

    # -------------------------------------------------------------------------
    # 12. Per-user cleanup (every uid >= 1000 plus $SUDO_USER, deduped)
    # -------------------------------------------------------------------------
    oem_tty_say "--> Cleaning per-user artefacts…"

    # Helper that removes all toolkit artefacts from a single home directory.
    # Accepts the home path as its first argument.
    _clean_user_home() {
        local home="$1"
        [ -d "$home" ] || return 0

        # Marker + autostart entries
        rm -f  "$home/.config/.oem-first-run-done"
        rm -f  "$home/.config/autostart/oem-first-run.desktop"
        rm -f  "$home/.config/autostart/touchegg-client.desktop"
        rm -f  "$home/.config/autostart/plank.desktop"
        rm -f  "$home/.config/autostart/imwheel.desktop"      # legacy
        rm -f  "$home/.imwheelrc"                             # legacy
        rm -f  "$home/.config/gtk-4.0/"{assets,gtk.css,gtk-dark.css}  # legacy

        # Plank dock config (current): dockitems + settings written by
        # oem-first-run.sh into ~/.config/plank/dock1/.
        rm -rf "$home/.config/plank"

        # LEGACY — XFCE panel-2 dock used by an earlier toolkit revision.
        # Keep this cleanup in place so users upgrading from the panel-2
        # build do not end up with orphaned launcher-NNN directories or
        # an empty panel-2 in their config. Safe no-op on fresh installs.
        local panel_dir="$home/.config/xfce4/panel"
        if [ -d "$panel_dir" ]; then
            for ldir in "$panel_dir"/launcher-[0-9]*; do
                [ -d "$ldir" ] || continue
                local lnum="${ldir##*launcher-}"
                if [ "$lnum" -ge 100 ] 2>/dev/null; then
                    rm -rf "$ldir"
                fi
            done
        fi
    }

    declare -A SEEN
    while IFS=: read -r u _ uid _ _ home _; do
        [ "$uid" -ge 1000 ] && [ "$uid" -lt 65534 ] || continue
        [ -n "${SEEN[$u]:-}" ] && continue
        SEEN[$u]=1
        _clean_user_home "$home"
    done < /etc/passwd

    if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null \
       && [ -z "${SEEN[$SUDO_USER]:-}" ]; then
        _clean_user_home "$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    fi

    # LEGACY — Remove panel-2 xfconf keys left behind by the older XFCE
    # panel-based dock revision so XFCE does not show an empty panel on
    # next login. Kept here for users upgrading from that build; on fresh
    # installs the keys do not exist and the calls are silent no-ops.
    # We do this via xfconf-query as root+sudo (the same env trick used
    # in step_themes).
    if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null \
       && command -v xfconf-query &>/dev/null; then
        local SUDO_HOME oem_dbus_addr=""
        SUDO_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        local pid
        pid=$(pgrep -u "$SUDO_USER" -x xfce4-session 2>/dev/null | head -1 || true)
        if [ -n "$pid" ] && [ -r "/proc/$pid/environ" ]; then
            oem_dbus_addr=$(tr '\0' '\n' < "/proc/$pid/environ" \
                | awk '/^DBUS_SESSION_BUS_ADDRESS=/{ print substr($0, index($0,"=")+1); exit }' || true)
        fi
        sudo -u "$SUDO_USER" env \
            HOME="$SUDO_HOME" \
            DISPLAY="${DISPLAY:-:0}" \
            XAUTHORITY="$SUDO_HOME/.Xauthority" \
            DBUS_SESSION_BUS_ADDRESS="${oem_dbus_addr:-}" \
            xfconf-query -c xfce4-panel -p /panels/panel-2 -r -R \
            2>/dev/null || true
        sudo -u "$SUDO_USER" env \
            HOME="$SUDO_HOME" \
            DISPLAY="${DISPLAY:-:0}" \
            XAUTHORITY="$SUDO_HOME/.Xauthority" \
            DBUS_SESSION_BUS_ADDRESS="${oem_dbus_addr:-}" \
            xfce4-panel --restart 2>/dev/null || true
    fi

    # -------------------------------------------------------------------------
    # 13. Clear oem-setup state markers so a future `setup.sh` doesn't think
    #     the toolkit is already applied.
    # -------------------------------------------------------------------------
    oem_tty_say "--> Clearing oem-setup state markers…"
    rm -rf /var/lib/oem-setup/state
    rm -f /var/lib/oem-setup/diagnostics-report.txt

    # -------------------------------------------------------------------------
    # 14. /tmp residue + final autoremove
    # -------------------------------------------------------------------------
    step_cleanup
    oem_run_log env DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y 2>/dev/null || true

    # -------------------------------------------------------------------------
    # 15. Closing summary
    # -------------------------------------------------------------------------
    oem_tty_say \
        "" \
        "=========================================" \
        "         UNINSTALL COMPLETE              " \
        "========================================="
    if [ ${#UNINSTALL_NOTES[@]} -gt 0 ]; then
        oem_tty_say "Best-effort caveats (items the toolkit cannot fully reverse):"
        for n in "${UNINSTALL_NOTES[@]}"; do
            oem_tty_say "  - $n"
        done
        oem_tty_say ""
    fi
    oem_tty_say \
        "Backups (if present) remain at: $BACKUP_DIR" \
        "Reboot is recommended to pick up grub/initramfs and keyboard changes." \
        "========================================="
}
