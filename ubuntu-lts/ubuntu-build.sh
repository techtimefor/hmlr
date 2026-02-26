#!/bin/bash

# --- 1. Configuration & Path Correction ---
BASE_DIR=$(pwd)
SOURCE_DIR="$BASE_DIR"
BUILD_DIR="$(pwd)/../../build"
OUTPUT_DIR="$(pwd)/../../output"
DATA_DIR="$(pwd)/../original_hml_data"
DATE_TAG=$(date +%Y%m%d)

# Branding Variables
HMLR_NAME="Hannah Montana Linux Revived"
UBUNTU_CODENAME="noble"

# --- 2. Staging & Permission Cleanup ---
echo "Cleaning staging area..."
sudo rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

[ -d "$SOURCE_DIR" ] && cp -r "$SOURCE_DIR/." "$BUILD_DIR/"

CHROOT="$BUILD_DIR/config/includes.chroot"
mkdir -p "$CHROOT/etc/skel/.trinity/share/config" \
         "$CHROOT/opt/trinity/share/apps/kdm/themes" \
         "$CHROOT/opt/trinity/share/icons" \
         "$CHROOT/usr/share/wallpapers" \
         "$CHROOT/usr/share/pixmaps" \
         "$CHROOT/etc/default" \
         "$CHROOT/usr/share/ubiquity/pixmaps" \
         "$CHROOT/usr/lib"

# --- 3. Identity Files (OS-Release & LSB-Release) ---
echo "Writing OS Identity..."

cat <<EOF > "$CHROOT/etc/lsb-release"
DISTRIB_ID=HMLR
DISTRIB_RELEASE=2026.1
DISTRIB_CODENAME=$UBUNTU_CODENAME
DISTRIB_DESCRIPTION="$HMLR_NAME"
EOF

cat <<EOF > "$CHROOT/etc/os-release"
PRETTY_NAME="$HMLR_NAME (24.04 LTS)"
NAME="$HMLR_NAME"
VERSION_ID="2026.1"
ID=hmlr
ID_LIKE=ubuntu
LOGO=hannah-montana-logo
EOF
cp "$CHROOT/etc/os-release" "$CHROOT/usr/lib/os-release"

# --- 4. Asset Mapping & Wallpaper Logic ---
echo "Mapping Wallpapers..."
cp "$DATA_DIR/wallpapers/hannah_montana_1.png" "$CHROOT/usr/share/wallpapers/hmlr_default.png"
cp "$DATA_DIR/wallpapers/hannah_montana_1.png" "$CHROOT/usr/share/pixmaps/hannah-montana-logo.png"

# Force TDE wallpaper
cat <<EOF > "$CHROOT/etc/skel/.trinity/share/config/kickerrc"
[Background]
Wallpaper=/usr/share/wallpapers/hmlr_default.png
WallpaperMode=Scaled
EOF

# Ubiquity Slideshow
cp "$DATA_DIR/wallpapers/hannah_montana_1.png" "$CHROOT/usr/share/ubiquity/pixmaps/sc_1.png"
cp "$DATA_DIR/wallpapers/hannah_montana_2.png" "$CHROOT/usr/share/ubiquity/pixmaps/sc_2.png"
cp "$DATA_DIR/wallpapers/hannah_montana_3.png" "$CHROOT/usr/share/ubiquity/pixmaps/sc_3.png"

echo "screenfetch" >> "$CHROOT/etc/skel/.bashrc"
echo "export UBUNTU_RELEASE='$HMLR_NAME'" > "$CHROOT/etc/default/ubiquity"

# --- 5. Dockerized Build with GPG Bypass ---
echo "Starting Docker Build (Addressing Key C93AF1698685AD8B)..."



docker run --privileged --rm \
    -v "$BUILD_DIR:/build" \
    -v "$OUTPUT_DIR:/output" \
    -w /build \
    ubuntu:noble /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update && apt-get install -y live-build curl wget gnupg squashfs-tools xorriso isolinux \
        ubiquity-casper casper libterm-readline-gnu-perl && \
        
        # 1. Setup Trinity Repo
        mkdir -p config/archives
        echo 'deb http://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-r14.1.x noble main deps' > config/archives/trinity.list.chroot
        
        # 2. THE NUCLEAR GPG FIX: 
        # We fetch the key and place it directly in config/archives as a .key file.
        # live-build will automatically import this into the chroot's trusted keys.
        gpg --keyserver hkps://keyserver.ubuntu.com --recv-key C93AF1698685AD8B
        gpg --export C93AF1698685AD8B > config/archives/trinity.key

        # 3. Keyring Package (Local)
        mkdir -p config/packages.chroot
        wget http://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-keyring.deb -O config/packages.chroot/trinity-keyring_all.deb

        # 4. lb config
        lb config \
            --mode ubuntu \
            --distribution $UBUNTU_CODENAME \
            --parent-distribution $UBUNTU_CODENAME \
            --parent-mirror-binary http://archive.ubuntu.com/ubuntu/ \
            --architectures amd64 \
            --binary-images iso-hybrid \
            --iso-application 'HMLR' \
            --bootloader syslinux \
            --archive-areas 'main restricted universe multiverse'

        # 5. Package List
        mkdir -p config/package-lists
        echo 'tde-trinity kubuntu-default-settings-trinity kubuntu-desktop-trinity screenfetch vlc ubiquity ubiquity-frontend-gtk casper network-manager xserver-xorg' > config/package-lists/hmlr.list.chroot

        # 6. Execute Build
        lb clean && lb build
        
        # 7. Verification Export
        if ls *.iso 1> /dev/null 2>&1; then
            mv *.iso /output/hmlr-revived-$DATE_TAG.iso
            echo 'SUCCESS: ISO EXPORTED'
        else
            echo 'FATAL ERROR: ISO build failed. Check logs above.'
            exit 1
        fi
    "

# Cleanup only if successful (or change to always cleanup)
sudo rm -rf "$BUILD_DIR"
