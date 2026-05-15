#!/bin/bash
# ==============================================================================
#   Module:    regional.sh
#   Purpose:   Two related responsibilities split across two functions so the
#              pipeline can run unattended:
#                prompt_keyboard — asks the technician once at the start
#                step_regional   — language packs, locale (PL), timezone
#                                  (Warsaw), keyboard layout, called late
#   Reads:     STATE_DIR/kb_layout (resume cache)
#              /dev/tty (read prompt)
#              helpers: ensure_apt_fresh, backup_once
#   Writes:    apt: language-pack-pl, language-pack-gnome-pl,
#                   language-pack-en, language-pack-gnome-en, locales
#              STATE_DIR/kb_layout                 (persisted choice)
#              /etc/locale.gen                    (via locale-gen)
#              /etc/default/locale                (via localectl)
#              /etc/timezone, /etc/localtime      (via timedatectl)
#              /etc/default/keyboard              (XKBLAYOUT, XKBVARIANT="")
#              /var/lib/oem-setup/backups/keyboard
#   Step fns:  prompt_keyboard, step_regional
#   Docs:      docs/modules/regional.md
#   Uninstall: step_uninstall purges language packs (sub-step 2), restores
#              /etc/default/keyboard or sed XKBLAYOUT="us" (sub-step 11),
#              resets locale to en_US.UTF-8 and timezone to UTC,
#              clears STATE_DIR (sub-step 14).
#
#   NOTE: prompt_keyboard reads from /dev/tty so it works under
#   `curl … | sudo bash`. Invalid input falls back to 'us' rather than
#   re-prompting (avoids infinite loops in scripted setups).
# ==============================================================================

prompt_keyboard() {
    if [ -f "$STATE_DIR/kb_layout" ]; then
        KB_LAYOUT=$(cat "$STATE_DIR/kb_layout")
        export KB_LAYOUT
        echo "    [i] Using saved keyboard layout from previous run: $KB_LAYOUT"
        echo "        (rm $STATE_DIR/kb_layout to be asked again)"
        return
    fi

    echo ""
    echo "========================================="
    echo " What is the PHYSICAL keyboard layout?  "
    echo " 1) US English (Standard)               "
    echo " 2) UK English (GB)                     "
    echo " 3) German (DE)                         "
    echo " 4) Swedish (SE)                        "
    echo " 5) Polish (PL)                         "
    echo "========================================="
    read -p "Enter number [1-5]: " kb_choice < /dev/tty

    case $kb_choice in
        1) KB_LAYOUT="us" ;;
        2) KB_LAYOUT="gb" ;;
        3) KB_LAYOUT="de" ;;
        4) KB_LAYOUT="se" ;;
        5) KB_LAYOUT="pl" ;;
        *) echo "Invalid input. Defaulting to US layout."; KB_LAYOUT="us" ;;
    esac
    export KB_LAYOUT
    echo "$KB_LAYOUT" > "$STATE_DIR/kb_layout"
    echo "    [+] Keyboard layout will be set to: $KB_LAYOUT"
}

step_regional() {
    # Prompt FIRST so the technician isn't left waiting on apt before being
    # asked. The full pipeline already calls prompt_keyboard at the very
    # start, so this branch only fires when menu option 13 is picked alone.
    if [ -z "${KB_LAYOUT:-}" ]; then
        prompt_keyboard
    fi

    echo "--> Configuring regional settings..."
    ensure_apt_fresh
    apt-get install -y language-pack-pl language-pack-gnome-pl \
                       language-pack-en language-pack-gnome-en \
                       locales

    # Belt-and-braces: language-pack-pl normally enables pl_PL.UTF-8 in
    # /etc/locale.gen, but on a fresh OEM image it's not always rebuilt
    # until the next boot. Generate explicitly so localectl can switch.
    locale-gen pl_PL.UTF-8 en_US.UTF-8 || true

    localectl set-locale LANG=pl_PL.UTF-8
    timedatectl set-timezone Europe/Warsaw

    echo "--> Applying $KB_LAYOUT physical keyboard layout..."
    backup_once /etc/default/keyboard
    sed -i "s/XKBLAYOUT=.*/XKBLAYOUT=\"$KB_LAYOUT\"/g" /etc/default/keyboard
    sed -i 's/^XKBVARIANT=.*/XKBVARIANT=""/g'           /etc/default/keyboard
    setupcon
}
