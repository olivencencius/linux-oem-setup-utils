#!/bin/bash

# Ensure the script is running as root
if [ "$EUID" -ne 0 ]; then 
  echo "Error: Please run this script with sudo."
  exit 1
fi

echo "========================================="
echo "        CHROMEBOOK STANDARD SETUP        "
echo "========================================="

# 1. Optimize Package Manager & Update System
echo "--> Updating package manager and running system updates..."
apt update && apt upgrade -y
echo "--> Installing codecs and default applications..."
apt install -y mint-meta-codecs git wget curl xinput gimp

# --> Install ZRAM (Memory Compression) and TLP (Battery Saver)
apt install -y zram-tools tlp
systemctl enable tlp
tlp start

# 2. Initialize and Enable Flathub Explicitly
echo "--> Setting up Flathub repository for third party apps..."
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# 3. Chromebook Hardware Fixes (Audio & Keyboard Mapping)
echo "--> Chromebook audio and keyboard optimizations..."
cd /tmp
git clone https://github.com/WeirdTreeThing/chromebook-linux-audio.git
cd chromebook-linux-audio && ./setup-audio && cd ..
git clone https://github.com/WeirdTreeThing/cros-keyboard-map.git
cd cros-keyboard-map && ./install.sh && cd ..

# 4. Hardware Fix Detector: CELES & TigerLake/AlderLake Patches
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
        cat <<EOF >> /etc/initramfs-tools/modules
cros-ec-typec
intel-pmc-mux
EOF
        update-initramfs -u -k all
    fi
fi

# 5. Install Official Google Chrome Browser (.deb)
echo "--> Downloading and installing Google Chrome..."
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt install -y ./google-chrome-stable_current_amd64.deb
rm google-chrome-stable_current_amd64.deb

# 6. Standard Applications Installation
echo "--> Installing default applications..."
apt install -y vlc
flatpak install flathub com.spotify.Client -y
flatpak install flathub org.supertuxkart.SuperTuxKart -y
flatpak install flathub org.gnome.Quadrapassel -y
flatpak install flathub org.gnome.Aisleriot -y

# 7. Apply System-Wide ChromeOS Aesthetics (For OEM Deployment)
echo "--> Downloading and caching modern ChromeOS visual themes..."
git clone https://github.com/vinceliuice/ChromeOS-theme.git
./ChromeOS-theme/install.sh -p /usr/share/themes
git clone https://github.com/vinceliuice/ChromeOS-icon-theme.git
./ChromeOS-icon-theme/src/install.sh -p /usr/share/icons

# 8. Hardware Tweaks: Touchpad Scrolling & Acceleration
echo "--> Configuring Touchpad properties (Natural Scrolling & Smooth Speed)..."
TP_ID=$(xinput list | grep -iE 'touchpad|trackpad' | grep -o 'id=[0-9]*' | cut -d= -f2)

if [ ! -z "$TP_ID" ]; then
    # Instant activation for the current OEM setup session
    xinput set-prop $TP_ID "libinput Natural Scrolling Enabled" 1
    xinput set-prop $TP_ID "libinput Accel Speed" -0.2
    
    # System-wide configuration to apply to any new user profiles created by the buyer
    mkdir -p /etc/X11/xorg.conf.d
    cat <<EOF > /etc/X11/xorg.conf.d/40-libinput-custom.conf
Section "InputClass"
        Identifier "touchpad catchall"
        MatchIsTouchpad "on"
        Option "NaturalScrolling" "true"
        Option "AccelSpeed" "-0.2"
        Driver "libinput"
EndSection
EOF
fi

# 9. Deploy Cloud-based Web App Shortcuts to Application Launcher
echo "--> Injecting premium Cloud Web-App launchers with official branding..."

# Ensure a system directory exists for the custom web icons
mkdir -p /usr/share/icons/hicolor/scalable/apps

APPS=(
  "Netflix|https://netflix.com|https://upload.wikimedia.org/wikipedia/commons/0/08/Netflix_2015_logo.svg" 
  "GoogleDocs|https://docs.google.com|https://upload.wikimedia.org/wikipedia/commons/0/01/Google_Docs_logo_%282014-2020%29.svg"
  "GoogleDrive|https://drive.google.com|https://commons.wikimedia.org/wiki/File:Google_Drive_icon_%282020%29.svg" 
  "Outlook|https://outlook.live.com|https://pl.wikipedia.org/wiki/Plik:Microsoft_Outlook_Icon_%282025%E2%80%93present%29.svg"
)

for app in "${APPS[@]}"; do
    NAME=$(echo $app | cut -d'|' -f1)
    URL=$(echo $app | cut -d'|' -f2)
    ICON_URL=$(echo $app | cut -d'|' -f3)
    ICON_PATH="/usr/share/icons/hicolor/scalable/apps/${NAME,,}.svg"

    # Download the official vector icon dynamically
    wget -qO "$ICON_PATH" "$ICON_URL"

    cat <<EOF > /usr/share/applications/${NAME}.desktop
[Desktop Entry]
Version=1.0
Name=${NAME}
Exec=google-chrome --app=${URL}
Terminal=false
Type=Application
Icon=${ICON_PATH}
Categories=Network;WebBrowser;
EOF
done

# 10. Regional Localization, Timezone & Physical Keyboard
echo "--> Configuring Regional Settings..."

# Download both Polish and English languages
apt install -y language-pack-pl language-pack-gnome-pl language-pack-en language-pack-gnome-en

# Set the system default language to Polish
localectl set-locale LANG=pl_PL.UTF-8

# Lock the Timezone to Warsaw, Poland
timedatectl set-timezone Europe/Warsaw

# Interactive Keyboard Selection (Reads from TTY to survive curl pipe)
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
localectl set-x11-keymap $KB_LAYOUT
sed -i "s/XKBLAYOUT=.*/XKBLAYOUT=\"$KB_LAYOUT\"/g" /etc/default/keyboard

# 11. Disable Bracketed Paste Mode (Fixes extra characters on paste)
echo "--> Disabling bracketed paste mode in terminal..."
mkdir -p /etc/skel
echo "set enable-bracketed-paste off" >> /etc/inputrc
echo "set enable-bracketed-paste off" >> /etc/skel/.inputrc
echo "set enable-bracketed-paste off" >> ~/.inputrc

echo "========================================="
echo "              SETUP COMPLETE!            "
echo "========================================="
