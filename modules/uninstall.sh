#!/bin/bash
# ==============================================================================
#   Module:    uninstall.sh
#   Purpose:   Best-effort reversal of every change this toolkit makes.
#              Restores from /var/lib/oem-setup/backups/ where possible;
#              falls back to sed-based line removal where no backup exists.
#   Reads:     SUDO_USER (optional), /dev/tty (YES confirmation)
#              /var/lib/oem-setup/backups/{grub,modules,inputrc,
#                                          keyboard,user}
#   Writes:    Reverts every system-level change the toolkit makes —
#              16 sub-steps detailed in docs/uninstall.md.
#              Notable: NOT removed are zenity/policykit-1/oem-config-gtk
#              (commonly part of Mint OEM images) and
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
        echo "    [+] Restored $target from backup."
        return 0
    fi
    return 1
}

step_uninstall() {
    echo ""
    echo "========================================="
    echo "         UNDO / FULL UNINSTALL           "
    echo "========================================="
    echo "This will remove every package and config change this toolkit made:"
    echo "  - Purge: Chrome, Zoom, VLC, GIMP, Plank, TLP, ZRAM tools, imwheel,"
    echo "          touchegg, xfdashboard, keyd, language packs, mint codecs,"
    echo "          games (SuperTuxKart, Aisleriot, Quadrapassel)"
    echo "  - Remove Google Chrome apt repository and signing key"
    echo "  - Remove Flathub remote"
    echo "  - Reverse-install ChromeOS GTK theme and Tela icon theme"
    echo "  - Revert /etc/default/grub, /etc/initramfs-tools/modules,"
    echo "          /etc/inputrc, /etc/default/keyboard, dconf profile"
    echo "  - Delete web-app .desktop entries, icons, wallpaper, oem-first-run"
    echo "  - Remove Powerwash tool, polkit policy and systemd finalize unit"
    echo "  - Clean /etc/skel and every user's home of toolkit artefacts"
    echo "  - Reset locale to en_US.UTF-8 and timezone to UTC"
    echo "  - Clear the oem-setup state markers and saved keyboard layout"
    echo "========================================="
    read -p "Type 'YES' (uppercase) to proceed, anything else to abort: " confirm < /dev/tty
    if [ "$confirm" != "YES" ]; then
        echo "Uninstall aborted."
        return 0
    fi
    echo ""

    # -------------------------------------------------------------------------
    # 1. Stop running services & user helpers BEFORE purging their packages
    # -------------------------------------------------------------------------
    echo "--> Stopping services..."
    for svc in tlp touchegg keyd oem-powerwash-finalize; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
            systemctl disable --now "$svc" 2>/dev/null || true
        fi
    done

    if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null; then
        sudo -u "$SUDO_USER" pkill -x imwheel              2>/dev/null || true
        sudo -u "$SUDO_USER" pkill -f 'touchegg --client'  2>/dev/null || true
        sudo -u "$SUDO_USER" pkill -x plank                2>/dev/null || true
        sudo -u "$SUDO_USER" pkill -x xfdashboard          2>/dev/null || true
    fi

    # -------------------------------------------------------------------------
    # 2. Apt purge — full scope (every package this toolkit installs)
    # -------------------------------------------------------------------------
    echo "--> Purging installed packages..."
    apt-get purge -y \
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
        mint-meta-codecs \
        language-pack-pl \
        language-pack-gnome-pl \
        language-pack-en \
        language-pack-gnome-en \
        touchegg \
        xfdashboard \
        wmctrl \
        xdotool \
        keyd \
        2>/dev/null || true

    apt-get autoremove --purge -y 2>/dev/null || true
    apt-get autoclean -y          2>/dev/null || true

    # -------------------------------------------------------------------------
    # 2b. Remove the Google Chrome apt repository and signing key that the
    #     Chrome .deb installs in its postinst. apt purge of the package does
    #     not remove these, and a future `apt update` will keep talking to
    #     Google.
    # -------------------------------------------------------------------------
    echo "--> Removing Google Chrome apt repository and signing key..."
    rm -f /etc/apt/sources.list.d/google-chrome.list \
          /etc/apt/sources.list.d/google.list \
          /etc/apt/trusted.gpg.d/google-chrome.gpg \
          /usr/share/keyrings/google-chrome.gpg
    apt-get update -qq 2>/dev/null || true

    # -------------------------------------------------------------------------
    # 3. Remove Flathub remote
    # -------------------------------------------------------------------------
    if command -v flatpak &>/dev/null; then
        echo "--> Removing Flathub remote..."
        flatpak remote-delete --force flathub 2>/dev/null || true
    fi

    # -------------------------------------------------------------------------
    # 4. Reverse-install themes via upstream installers (support -r flag)
    # -------------------------------------------------------------------------
    echo "--> Reverse-installing ChromeOS GTK theme and Tela icons..."
    cd /tmp
    rm -rf ChromeOS-theme Tela-icon-theme

    if git clone --depth 1 https://github.com/vinceliuice/ChromeOS-theme.git 2>/dev/null; then
        ./ChromeOS-theme/install.sh -r 2>/dev/null \
            || note "ChromeOS-theme uninstall failed — residual files may exist under /usr/share/themes/ChromeOS*"
    else
        note "Could not clone ChromeOS-theme to reverse-install — remove /usr/share/themes/ChromeOS* manually if desired."
    fi

    if git clone --depth 1 https://github.com/vinceliuice/Tela-icon-theme.git 2>/dev/null; then
        ./Tela-icon-theme/install.sh -r 2>/dev/null \
            || note "Tela-icon-theme uninstall failed — residual files may exist under /usr/share/icons/Tela*"
    else
        note "Could not clone Tela-icon-theme to reverse-install — remove /usr/share/icons/Tela* manually if desired."
    fi

    rm -rf /tmp/ChromeOS-theme /tmp/Tela-icon-theme

    # -------------------------------------------------------------------------
    # 5. Chromebook-linux-audio quirks (best-effort; upstream has no uninstaller)
    # -------------------------------------------------------------------------
    echo "--> Cleaning chromebook-linux-audio quirks (best-effort)..."
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
    # 6. Hardware-fix config: GRUB + initramfs-tools/modules
    # -------------------------------------------------------------------------
    echo "--> Reverting /etc/default/grub..."
    if ! restore_or_skip /etc/default/grub; then
        if [ -f /etc/default/grub ]; then
            sed -i 's/clocksource=hpet hpet=force //g' /etc/default/grub
            echo "    [+] Removed 'clocksource=hpet hpet=force' from GRUB_CMDLINE_LINUX_DEFAULT."
        fi
    fi
    if command -v update-grub &>/dev/null; then
        update-grub 2>/dev/null || true
    fi

    echo "--> Reverting /etc/initramfs-tools/modules..."
    if ! restore_or_skip /etc/initramfs-tools/modules; then
        if [ -f /etc/initramfs-tools/modules ]; then
            sed -i -e '/^cros-ec-typec$/d' -e '/^intel-pmc-mux$/d' \
                /etc/initramfs-tools/modules
            echo "    [+] Removed 'cros-ec-typec' / 'intel-pmc-mux' lines."
        fi
    fi
    if command -v update-initramfs &>/dev/null; then
        update-initramfs -u -k all 2>/dev/null || true
    fi

    # -------------------------------------------------------------------------
    # 7. Touchpad / gestures config
    # -------------------------------------------------------------------------
    echo "--> Removing touchpad and gestures config..."
    rm -f /etc/X11/xorg.conf.d/40-chromebook-touchpad.conf
    rm -f /etc/touchegg/touchegg.conf
    rmdir --ignore-fail-on-non-empty /etc/touchegg 2>/dev/null || true

    # -------------------------------------------------------------------------
    # 8. Themes / dock / wallpaper / first-run script
    # -------------------------------------------------------------------------
    echo "--> Removing dock, wallpaper, and first-run script..."
    rm -f /etc/xdg/autostart/plank.desktop
    rm -f /etc/dconf/db/local.d/00-plank
    if command -v dconf &>/dev/null; then
        dconf update 2>/dev/null || true
    fi

    if ! restore_or_skip /etc/dconf/profile/user; then
        if [ -f /etc/dconf/profile/user ]; then
            sed -i -e '/^user-db:user$/d' -e '/^system-db:local$/d' \
                /etc/dconf/profile/user
            [ ! -s /etc/dconf/profile/user ] && rm -f /etc/dconf/profile/user
        fi
    fi

    rm -rf /usr/share/backgrounds/oem-setup
    rm -f  /usr/local/bin/oem-first-run.sh

    # -------------------------------------------------------------------------
    # 8b. Powerwash tool — scripts, systemd unit, polkit policy, menu entry,
    #     icon, and any pending flag file.
    #     oem-config-gtk and zenity are NOT purged here because they are
    #     commonly part of the Mint OEM image already.
    # -------------------------------------------------------------------------
    echo "--> Removing Powerwash tool..."
    systemctl disable oem-powerwash-finalize.service 2>/dev/null || true
    rm -f /etc/systemd/system/oem-powerwash-finalize.service
    systemctl daemon-reload 2>/dev/null || true
    rm -f /usr/local/bin/oem-powerwash.sh
    rm -f /usr/local/sbin/oem-powerwash-arm.sh
    rm -f /usr/local/sbin/oem-powerwash-finalize.sh
    rm -f /usr/share/applications/oem-powerwash.desktop
    rm -f /usr/share/icons/hicolor/scalable/apps/oem-powerwash.svg
    rm -f /usr/share/polkit-1/actions/org.linuxoem.powerwash.policy
    rm -f /var/lib/oem-setup/powerwash.flag
    rm -f /var/log/oem-powerwash.log
    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database /usr/share/applications 2>/dev/null || true
    fi

    # -------------------------------------------------------------------------
    # 9. Web-app shortcuts (.desktop + icons)
    # -------------------------------------------------------------------------
    echo "--> Removing web-app shortcuts and icons..."
    local WEBAPP_NAMES=(
        Netflix PrimeVideo DisneyPlus HBOMax Spotify YouTube
        Gmail GoogleDocs GoogleDrive Gemini ChromeRemoteDesktop
    )
    local ICON_NAMES=(
        netflix primevideo disneyplus hbomax spotify youtube
        gmail googledocs googledrive gemini chromeremotedesktop
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
    # 10. Terminal — bracketed paste fix
    # -------------------------------------------------------------------------
    echo "--> Reverting terminal paste fix..."
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
    # 11. Regional — keyboard, locale, timezone
    # -------------------------------------------------------------------------
    echo "--> Reverting regional settings..."
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
    # 12. /etc/skel cleanup — files this toolkit placed there
    # -------------------------------------------------------------------------
    echo "--> Cleaning /etc/skel artefacts..."
    rm -f  /etc/skel/.imwheelrc
    rm -f  /etc/skel/.config/autostart/imwheel.desktop
    rm -f  /etc/skel/.config/autostart/plank.desktop
    rm -f  /etc/skel/.config/autostart/oem-first-run.desktop
    rm -f  /etc/skel/.config/autostart/touchegg-client.desktop
    rm -rf /etc/skel/.config/plank
    rm -f  /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml
    # Libadwaita symlinks staged by step_themes for new users.
    rm -f  /etc/skel/.config/gtk-4.0/{assets,gtk.css,gtk-dark.css}
    rmdir --ignore-fail-on-non-empty -p \
        /etc/skel/.config/autostart \
        /etc/skel/.config/gtk-4.0 \
        /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml \
        2>/dev/null || true

    # /root/.config/gtk-4.0 — created so upstream's install.sh wouldn't crash.
    # Drop the symlinks it deposited, then prune the dir if empty.
    rm -f /root/.config/gtk-4.0/{assets,gtk.css,gtk-dark.css}
    rmdir --ignore-fail-on-non-empty /root/.config/gtk-4.0 2>/dev/null || true

    # -------------------------------------------------------------------------
    # 13. Per-user cleanup (every uid >= 1000 plus $SUDO_USER, deduped)
    # -------------------------------------------------------------------------
    echo "--> Cleaning per-user artefacts..."
    declare -A SEEN
    while IFS=: read -r u _ uid _ _ home _; do
        [ "$uid" -ge 1000 ] && [ "$uid" -lt 65534 ] || continue
        [ -n "${SEEN[$u]:-}" ] && continue
        SEEN[$u]=1

        [ -d "$home" ] || continue
        rm -f  "$home/.imwheelrc"
        rm -f  "$home/.config/.oem-first-run-done"
        rm -f  "$home/.config/autostart/oem-first-run.desktop"
        rm -f  "$home/.config/autostart/touchegg-client.desktop"
        rm -f  "$home/.config/autostart/plank.desktop"
        rm -f  "$home/.config/autostart/imwheel.desktop"
        rm -rf "$home/.config/plank"
        rm -f  "$home/.config/gtk-4.0/"{assets,gtk.css,gtk-dark.css}
    done < /etc/passwd

    if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null \
       && [ -z "${SEEN[$SUDO_USER]:-}" ]; then
        SUDO_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        rm -f  "$SUDO_HOME/.imwheelrc"
        rm -f  "$SUDO_HOME/.config/.oem-first-run-done"
        rm -f  "$SUDO_HOME/.config/autostart/oem-first-run.desktop"
        rm -f  "$SUDO_HOME/.config/autostart/touchegg-client.desktop"
        rm -f  "$SUDO_HOME/.config/autostart/plank.desktop"
        rm -f  "$SUDO_HOME/.config/autostart/imwheel.desktop"
        rm -rf "$SUDO_HOME/.config/plank"
        rm -f  "$SUDO_HOME/.config/gtk-4.0/"{assets,gtk.css,gtk-dark.css}
    fi

    # -------------------------------------------------------------------------
    # 14. Clear oem-setup state markers so a future `setup.sh` doesn't think
    #     the toolkit is already applied.
    # -------------------------------------------------------------------------
    echo "--> Clearing oem-setup state markers..."
    rm -rf /var/lib/oem-setup/state

    # -------------------------------------------------------------------------
    # 15. /tmp residue + final autoremove
    # -------------------------------------------------------------------------
    step_cleanup
    apt-get autoremove --purge -y 2>/dev/null || true

    # -------------------------------------------------------------------------
    # 16. Closing summary
    # -------------------------------------------------------------------------
    echo ""
    echo "========================================="
    echo "         UNINSTALL COMPLETE              "
    echo "========================================="
    if [ ${#UNINSTALL_NOTES[@]} -gt 0 ]; then
        echo "Best-effort caveats (items the toolkit cannot fully reverse):"
        for n in "${UNINSTALL_NOTES[@]}"; do
            echo "  - $n"
        done
        echo ""
    fi
    echo "Backups (if present) remain at: $BACKUP_DIR"
    echo "Reboot is recommended to pick up grub/initramfs and keyboard changes."
    echo "========================================="
}
