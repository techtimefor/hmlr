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
    export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
      live-build curl wget gnupg squashfs-tools xorriso \
      syslinux-utils syslinux-common isolinux mtools \
      dosfstools genisoimage

    # FIXING THE GPG ERROR (NO_PUBKEY C93AF1698685AD8B)
    mkdir -p config/archives
    echo 'deb http://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-r14.1.x noble main deps' > config/archives/trinity.list.chroot
    
    # Manually download the keyring .deb and extract the key
    wget http://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-keyring.deb
    dpkg -x trinity-keyring.deb /tmp/keyring
    cp /tmp/keyring/usr/share/keyrings/trinity-archive-keyring.gpg config/archives/trinity.key.chroot
    cp config/archives/trinity.key.chroot config/archives/trinity.key.binary

    # Configure Live-Build
    lb config \
      --mode ubuntu \
      --distribution noble \
      --binary-images iso-hybrid \
      --architectures amd64 \
      --archive-areas 'main restricted universe multiverse'

    # Package List (Trinity + Calamares)
    echo 'tde-trinity calamares calamares-settings-ubuntu vlc' > config/package-lists/hmlr.list.chroot

    # Build the ISO
    lb build

    # Move result to output
    mv *.iso /output/hmlr-v4-trinity.iso || echo 'Build Failed'
"
