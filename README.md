# 🚀 Chromebook Linux Mint OEM Deployment

A fully automated, production-grade deployment script designed to convert unlocked x86/Intel Chromebooks into high-performance, market-ready laptops running **Linux Mint XFCE**. 

Optimized strictly for resale velocity, out-of-the-box driver reliability, and a premium user experience on lower-tier (4GB RAM) hardware.

---

## 🌟 Key Features

### ⚡ Performance & Battery Optimization
* **ZRAM Memory Compression:** Prevents system stuttering on 4GB RAM machines by compressing memory instead of using slow eMMC swap space.
* **TLP Power Management:** Automatically under-volts and manages hardware power states to maximize battery life, mimicking native ChromeOS battery performance.

### 🛠️ Automated Hardware Fixes
* **Audio & Keyboard:** Clones and compiles standard `chromebook-linux-audio` and `cros-keyboard-map` fixes for top-row functional keys.
* **Smart Board Detectors:** * Automatically injects `hpet=force` kernel parameters to prevent freezing on **CELES** (Samsung) boards.
  * Forces `cros-ec-typec` driver mapping for **TigerLake/AlderLake** CPUs to fix dead USB-C ports.
* **Touchpad Calibration:** Enforces **Natural Scrolling (Reverse)** and applies smooth pointer acceleration (`-0.2`) to prevent lag on cheaper touchpads.

### 📦 Software & Productivity
* **Google Chrome:** Installs the official `.deb` to ensure seamless background updates.
* **Core Apps & Flathub:** Pre-configures Flathub and installs essential apps (VLC, GIMP, Spotify).
* **Family-Friendly Games:** Includes lightweight, native games (SuperTuxKart, Quadrapassel/Tetris, Aisleriot Solitaire) to boost perceived out-of-the-box value without bloating storage.

### ☁️ Cloud Web-App Integration
Injects native-looking desktop shortcuts for premium web services using official high-res SVG branding:
* Netflix
* Google Docs
* Google Drive
* Microsoft Outlook

### 🎨 Premium Aesthetics & UX
* **ChromeOS Look:** Automatically applies the modern ChromeOS GTK theme and Icon set system-wide.
* **Terminal Fix:** Disables "Bracketed Paste Mode" globally to prevent garbage characters (`0~`, `1~`) when pasting text into the terminal.
---

## 📋 Deployment Instructions (The Flipping Workflow)

1. **Install OS:** Boot your custom Linux Mint XFCE USB on the target Chromebook.
2. **OEM Mode:** In the GRUB boot menu, select **OEM Install (for manufacturers)**.
3. **Initial Setup:** Complete the default installer prompts.
4. **Boot & Connect:** Reboot the laptop and boot directly into the temporary `oem` workspace profile. Connect to Wi-Fi.
5. **Execute Script:** Open the terminal window and run the following command (replace with your actual GitHub repo details):

   ```bash
   curl -sL [https://raw.githubusercontent.com/](https://raw.githubusercontent.com/)olivencencius/linux-oem-setup-utils/main/setup.sh | sudo bash
