#!/bin/bash
# --- 1. Paths & Configuration ---
BASE_DIR=$(pwd)
BUILD_DIR="$BASE_DIR/build"
OUTPUT_DIR="$BASE_DIR/output"
DATA_DIR="$BASE_DIR/original_hml_data"
CHROOT="$BUILD_DIR/config/includes.chroot"

HMLR_NAME="Hannah Montana Linux Revived V4"
UBUNTU_CODENAME="noble"

echo "--- Initializing HMLR V4 Build Environment ---"

# --- 2. Clean & Setup ---
sudo rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
mkdir -p "$CHROOT/etc/skel/.trinity/share/config"
mkdir -p "$CHROOT/usr/lib"
mkdir -p "$CHROOT/usr/share/calamares/branding/hmlr"

# --- 3. IDENTITY & BRANDING ---
cat <<EOF > "$CHROOT/etc/os-release"
PRETTY_NAME="$HMLR_NAME"
NAME="$HMLR_NAME"
ID=hmlr
ID_LIKE=ubuntu
ANSI_COLOR="1;35"
EOF
cp "$CHROOT/etc/os-release" "$CHROOT/usr/lib/os-release"

# --- 4. TRINITY TRANSLATION (KDE4 to TDE) ---
echo "Translating KDE4 Theme Data for Trinity..."

# Map the Pink colors into the global Trinity config
cat <<EOF > "$CHROOT/etc/skel/.trinity/share/config/kdeglobals"
[General]
activeBackground=255,105,180
activeForeground=255,255,255
inactiveBackground=220,150,200
widgetStyle=plastik

[Icons]
Theme=hannah_montana

[WM]
active=255,105,180
inactive=220,150,200
EOF

# --- 5. CALAMARES (HOT PINK INSTALLER) ---
cat <<EOF > "$CHROOT/usr/share/calamares/branding/hmlr/branding.desc"
---
componentName:  hmlr
welcomeStyleCalamares:   true
welcomeExpandingLogo:   true
shortProductName:   HMLR
productName:        Hannah Montana Linux
sidebarBackground:  "#FF69B4"
sidebarText:        "#FFFFFF"
EOF

# --- 6. DOCKERIZED BUILD WITH GPG FIX ---
docker run --privileged --rm \
  -v "$BUILD_DIR:/build" \
  -v "$OUTPUT_DIR:/output" \
  -v "$DATA_DIR:/data" \
  -w /build \
  ubuntu:noble /bin/bash -c "
    set -e
    export DEBIAN_FRONTEND=noninteractive

    # 1. Install Build Tools
    apt-get update && apt-get install -y \
      live-build curl wget gnupg squashfs-tools xorriso \
      syslinux-utils syslinux-common isolinux calamares \
      mtools dosfstools genisoimage

    # 2. FIX TRINITY REPO & GPG (The Noble Way)
    mkdir -p config/archives
    echo 'deb http://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-r14.1.x noble main deps' > config/archives/trinity.list.chroot
    
    # Download and De-armor the key (Mandatory for Ubuntu 24.04)
    wget -qO- http://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-keyring.gpg | gpg --dearmor > config/archives/trinity.key.chroot
    cp config/archives/trinity.key.chroot config/archives/trinity.key.binary

    # 3. SURGICAL PATCH: Binary.sh Overwrite
    # This ensures the ISO is hybrid-compatible for USB booting
    mkdir -p scripts
    cat <<'INNEREOF' > scripts/binary.sh
#!/bin/sh
echo 'RUNNING HMLR PATCHED BINARY SCRIPT...'
lb binary_linux-image
lb binary_syslinux
lb binary_iso
INNEREOF
    chmod +x scripts/binary.sh

    # 4. Configure Live-Build
    lb config \
      --mode ubuntu \
      --distribution noble \
      --binary-images iso-hybrid \
      --architectures amd64 \
      --linux-flavours generic \
      --archive-areas 'main restricted universe multiverse'

    # 5. Package List: Trinity + Calamares + Plastik Theme
    mkdir -p config/package-lists
    echo 'tde-trinity tde-style-plastik-trinity calamares calamares-settings-ubuntu vlc' > config/package-lists/hmlr.list.chroot

    # 6. Execute Build
    lb clean --purge
    lb build

    # 7. Dynamic Export Logic
    # Find the generated ISO and move it to the mounted output folder
    ISO_FILE=\$(ls *.iso 2>/dev/null | head -n 1)
    if [ -n \"\$ISO_FILE\" ]; then
        mv \"\$ISO_FILE\" /output/hmlr-v4-trinity.iso
        echo 'SUCCESS: ISO EXPORTED TO OUTPUT FOLDER'
    else
        echo 'FATAL ERROR: Build completed but no ISO found'
        exit 1
    fi
"
