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
echo "Starting Docker Build with surgical script patch..."
docker run --privileged --rm \
  -v "$(pwd)/../../build:/build" \
  -v "$(pwd)/../../output:/output" \
  -w /build \
  ubuntu:noble /bin/bash -c "
    export DEBIAN_FRONTEND=noninteractive
    
    # 1. Prepare Environment & Fix Paths
    apt-get update && apt-get install -y \
      live-build curl wget gnupg squashfs-tools xorriso \
      syslinux-utils syslinux-common isolinux \
      mtools dosfstools genisoimage

    # 2. OVERWRITE THE TROUBLEMAKER binary.sh
    cat <<'INNEREOF' > /build/binary.sh
#!/bin/sh
echo 'RUNNING PATCHED BINARY.SH...'
genisoimage -J -l -cache-inodes -allow-multidot \
  -A \"HMLR_REVIVED\" \
  -p \"live-build 3.0\" \
  -publisher \"HMLR Project\" \
  -V \"HMLR_2026\" \
  -o binary.hybrid.iso binary
isohybrid binary.hybrid.iso
INNEREOF
    chmod +x /build/binary.sh

    # 3. Trinity Repo Setup (Original Stable Logic)
    mkdir -p config/archives
    echo 'deb http://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-r14.1.x noble main deps' > config/archives/trinity.list.chroot
    wget -qO- 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xC93AF1698685AD8B' | gpg --dearmor > config/archives/trinity.key.chroot
    cp config/archives/trinity.key.chroot config/archives/trinity.key.binary

    # 4. Config & Package Lists
    lb config \
      --mode ubuntu \
      --distribution noble \
      --binary-images iso-hybrid \
      --bootloader isolinux \
      --archive-areas 'main restricted universe multiverse'
    
    mkdir -p config/package-lists
    echo 'kubuntu-default-settings-trinity kubuntu-desktop-trinity ubiquity vlc' > config/package-lists/hmlr.list.chroot

    # 5. Execute Build
    lb build

    # 6. Export Results
    if [ -f binary.hybrid.iso ]; then
        mv binary.hybrid.iso /output/hmlr-revived-V4.iso
        echo 'SUCCESS: ISO EXPORTED TO OUTPUT FOLDER'
    else
        echo 'FATAL ERROR: Build failed to produce ISO'
        exit 1
    fi
"
