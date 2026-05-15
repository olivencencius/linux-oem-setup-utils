#!/bin/bash

# Ensure the script is running as root
if [ "$EUID" -ne 0 ]; then 
  echo "Error: Please run this script with sudo."
  exit 1
fi

# ==============================================================================
#                             MODULAR FUNCTIONS
# ==============================================================================

step_cleanup() {
    echo "--> Cleaning up temporary files from any previous partial runs..."
    rm -rf /tmp/chromebook-linux-audio /tmp/cros-keyboard-map /tmp/ChromeOS-themes /tmp/Tela-icon-theme
}

step_updates() {
    echo "--> Updating package manager and running system updates..."
    apt update && apt upgrade -y
    echo "--> Installing codecs and default applications..."
    apt install -y mint-meta-codecs git wget curl xinput gimp
    
    echo "--> Installing ZRAM (Memory Compression) and TLP (Battery Saver)..."
    apt install -y zram-tools tlp
    systemctl enable tlp
    tlp start
}

step_flathub() {
    echo "--> Setting up Flathub repository for third party apps..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak update -y
}

step_hardware_fixes() {
    echo "--> Chromebook audio and keyboard optimizations..."
    cd /tmp
    git clone https://github.com/WeirdTreeThing/chromebook-linux-audio.git
    cd chromebook-linux-audio && ./setup-audio

    cd /tmp
    git clone https://github.com/WeirdTreeThing/cros-keyboard-map.git
    cd cros-keyboard-map && ./install.sh

    echo "--> Analyzing motherboard architecture for specialized upstream patches..."
    # Fix for CELES boards (Freezing mitigation via HPET clock)
    if dmesg | grep -qi "celes"; then
        echo "    [!] CELES Board detected. Injecting HPET kernel clock parameters..."
        if ! grep -q "clocksource=hpet" /etc/default/grub; then
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="clocksource=hpet hpet=force /' /etc/default/grub
            update-grub
        fi
    fi

    # Fix for TigerLake/AlderLake USB-C module dropping
    if lscpu | grep -qiE "tiger|alder"; then
        echo "    [!] Tiger/AlderLake CPU detected. Forcing Type-C driver stack mapping..."
        if ! grep -q "cros-ec-typec" /etc/initramfs-tools/modules; then
            echo "cros-ec-typec" >> /etc/initramfs-tools/modules
            echo "intel-pmc-mux" >> /etc/initramfs-tools/modules
            update-initramfs -u -k all
        fi
    fi
}

step_chrome() {
    echo "--> Downloading and installing Google Chrome..."
    cd /tmp
    wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    apt install -y ./google-chrome-stable_current_amd64.deb
    rm google-chrome-stable_current_amd64.deb
}

step_apps() {
    echo "--> Installing default applications..."
    apt install -y vlc
    flatpak install flathub com.spotify.Client -y --noninteractive
    flatpak install flathub org.supertuxkart.SuperTuxKart -y --noninteractive
    flatpak install flathub org.gnome.Quadrapassel -y --noninteractive
    flatpak install flathub org.gnome.Aisleriot -y --noninteractive
}

step_themes() {
    echo "--> Downloading and caching modern ChromeOS visual themes..."
    cd /tmp
    git clone https://github.com/vinceliuice/ChromeOS-themes.git
    ./ChromeOS-themes/install.sh -p /usr/share/themes

    cd /tmp
    git clone https://github.com/vinceliuice/Tela-icon-theme.git
    ./Tela-icon-theme/install.sh -a -d /usr/share/icons
}

step_touchpad() {
    echo "--> Configuring Touchpad properties (Natural Scrolling & Smooth Speed)..."
    TP_ID=$(xinput list | grep -iE 'touchpad|trackpad' | grep -o 'id=[0-9]*' | cut -d= -f2)

    if [ ! -z "$TP_ID" ]; then
        xinput set-prop $TP_ID "libinput Natural Scrolling Enabled" 1
        xinput set-prop $TP_ID "libinput Accel Speed" -0.2
        
        mkdir -p /etc/X11/xorg.conf.d
        CONF_FILE="/etc/X11/xorg.conf.d/40-libinput-custom.conf"
        echo 'Section "InputClass"' > "$CONF_FILE"
        echo '        Identifier "touchpad catchall"' >> "$CONF_FILE"
        echo '        MatchIsTouchpad "on"' >> "$CONF_FILE"
        echo '        Option "NaturalScrolling" "true"' >> "$CONF_FILE"
        echo '        Option "AccelSpeed" "-0.2"' >> "$CONF_FILE"
        echo '        Driver "libinput"' >> "$CONF_FILE"
        echo 'EndSection' >> "$CONF_FILE"
    fi
}

step_web_apps() {
    echo "--> Injecting premium Cloud Web-App launchers with official branding..."
    mkdir -p /usr/share/icons/hicolor/scalable/apps

    APPS=(
      "Netflix|https://netflix.com|https://upload.wikimedia.org/wikipedia/commons/0/08/Netflix_2015_logo.svg" 
      "GoogleDocs|https://docs.google.com|https://upload.wikimedia.org/wikipedia/commons/0/01/Google_Docs_logo_%282014-2020%29.svg"
      "GoogleDrive|https://drive.google.com|https://commons.wikimedia.org/wiki/File:Google_Drive_icon_%282020%29.svg" 
      "Outlook|https://outlook.live.com|https://pl.wikipedia.org/wiki/Plik:Microsoft_Outlook_Icon_%282025%E2%80%93present%29.svg"
    )

    for app in "${APPS[@]}"; do
        NAME=$(echo "$app" | cut -d'|' -f1)
        URL=$(echo "$app" | cut -d'|' -f2)
        ICON_URL=$(echo "$app" | cut -d'|' -f3)
        ICON_PATH="/usr/share/icons/hicolor/scalable/apps/${NAME,,}.svg"

        wget -qO "$ICON_PATH" "$ICON_URL"

        DESKTOP_FILE="/usr/share/applications/${NAME}.desktop"
        echo "[Desktop Entry]" > "$DESKTOP_FILE"
        echo "Version=1.0" >> "$DESKTOP_FILE"
        echo "Name=${NAME}" >> "$DESKTOP_FILE"
        echo "Exec=google-chrome --app=${URL}" >> "$DESKTOP_FILE"
        echo "Terminal=false" >> "$DESKTOP_FILE"
        echo "Type=Application" >> "$DESKTOP_FILE"
        echo "Icon=${ICON_PATH}" >> "$DESKTOP_FILE"
        echo "Categories=Network;WebBrowser;" >> "$DESKTOP_FILE"
    done
}

step_terminal() {
    echo "--> Disabling bracketed paste mode in terminal..."
    mkdir -p /etc/skel
    echo "set enable-bracketed-paste off" >> /etc/inputrc
    echo "set enable-bracketed-paste off" >> /etc/skel/.inputrc
    echo "set enable-bracketed-paste off" >> ~/.inputrc
}

step_regional() {
    echo "--> Configuring Regional Settings..."
    apt install -y language-pack-pl language-pack-gnome-pl language-pack-en language-pack-gnome-en
    localectl set-locale LANG=pl_PL.UTF-8
    timedatectl set-timezone Europe/Warsaw

    echo ""
    echo "========================================="
    echo " What is the PHYSICAL keyboard layout? "
    echo " 1) US English (Standard)"
    echo " 2) UK English (GB)"
    echo " 3) German (DE)"
    echo " 4) Swedish (SE)"
    echo " 5) Polish (PL)"
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

    echo "--> Applying $KB_LAYOUT physical keyboard layout..."
    sed -i "s/XKBLAYOUT=.*/XKBLAYOUT=\"$KB_LAYOUT\"/g" /etc/default/keyboard
    setupcon
}

run_full_pipeline() {
    step_cleanup
    step_updates
    step_flathub
    step_hardware_fixes
    step_chrome
    step_apps
    step_themes
    step_touchpad
    step_web_apps
    step_terminal
    step_regional
}

# ==============================================================================
#                                INTERACTIVE MENU
# ==============================================================================

while true; do
    echo ""
    echo "========================================="
    echo "        CHROMEBOOK DEPLOYMENT ENGINE     "
    echo "========================================="
    echo " 1) Run entire pipeline (Recommended for fresh setup)"
    echo " 2) Run system updates and dependencies installations"
    echo " 3) Run flathub initializations (3rd party apps)"
    echo " 4) Run Chromebook Hardware Fixes & Patches"
    echo " 5) Install Google Chrome"
    echo " 6) Install Standard Apps (VLC/Spotify/Games)"
    echo " 7) Apply ChromeOS Themes & Icons"
    echo " 8) Apply Touchpad Calibration"
    echo " 9) Inject Branded Web Apps"
    echo " 10) Apply Terminal Paste Fix"
    echo " 11) Adjust Region, Language & Keyboard Layout"
    echo " 12) Exit Setup"
    echo "========================================="
    read -p "Select choice [1-12]: " main_choice < /dev/tty
    echo ""

    case $main_choice in
        1)  run_full_pipeline; break ;;
        2)  step_cleanup; step_updates ;;
        3)  step_flathub ;;
        4)  step_cleanup; step_hardware_fixes ;;
        5)  step_chrome ;;
        6)  step_apps ;;
        7)  step_cleanup; step_themes ;;
        8)  step_touchpad ;;
        9)  step_web_apps ;;
        10) step_terminal ;;
        11) step_regional ;;
        12) echo "Exiting configuration engine."; break ;;
        *)  echo "Invalid option. Please choose 1-12." ;;
    esac
done

echo "========================================="
echo "              OPERATION END              "
echo "========================================="
