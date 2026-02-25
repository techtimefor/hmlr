#!/bin/bash

# --- 1. Configuration & Path Correction ---
# Based on your terminal, the script runs in hmlr/ubuntu-lts/
# So DATA_DIR is ../original_hml_data
BASE_DIR=$(pwd)
SOURCE_DIR="$BASE_DIR"
BUILD_DIR="$(pwd)/../../build"
OUTPUT_DIR="$(pwd)/../../output"
DATA_DIR="$(pwd)/../original_hml_data"
DATE_TAG=$(date +%Y%m%d)

# Branding
HMLR_NAME="Hannah Montana Linux Revived"
UBUNTU_CODENAME="noble"

# --- 2. Staging & Permission Cleanup ---
echo "Cleaning staging area..."
sudo rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# Copy base live-build structure
[ -d "$SOURCE_DIR" ] && cp -r "$SOURCE_DIR/." "$BUILD_DIR/"

CHROOT="$BUILD_DIR/config/includes.chroot"
mkdir -p "$CHROOT/etc/skel/.trinity/share/config" \
         "$CHROOT/opt/trinity/share/apps/kdm/themes" \
         "$CHROOT/opt/trinity/share/icons" \
         "$CHROOT/usr/share/pixmaps" \
         "$CHROOT/etc/default" \
         "$CHROOT/usr/share/ubiquity/pixmaps" \
         "$CHROOT/usr/lib"

# --- 3. Asset Extraction & Mapping ---
echo "Extracting and Mapping Purple Assets..."
TEMP_EXTRACT=$(mktemp -d)

# Fixed extraction paths based on your screenshot
tar -xJf "$DATA_DIR/icons.tar.xz" -C "$TEMP_EXTRACT/"
tar -xzf "$DATA_DIR/skel.tar.gz" -C "$TEMP_EXTRACT/"

# Map themes and icons
find "$TEMP_EXTRACT" -type d -name "hannah_montana" -path "*/icons/*" -exec cp -r {} "$CHROOT/opt/trinity/share/icons/" \;
find "$TEMP_EXTRACT" -type d -name "hannah_montana" -path "*/kdm/themes/*" -exec cp -r {} "$CHROOT/opt/trinity/share/apps/kdm/themes/" \;

# Copy Main Logo
cp "$DATA_DIR/wallpapers/hannah_montana_1.png" "$CHROOT/usr/share/pixmaps/hannah-montana-logo.png"

# --- 4. Installer Slideshow (Ubiquity) ---
echo "Setting up Installer Slideshow..."
# Using the specific files seen in your 'wallpapers' folder screenshot
cp "$DATA_DIR/wallpapers/hannah_montana_1.png" "$CHROOT/usr/share/ubiquity/pixmaps/sc_1.png"
cp "$DATA_DIR/wallpapers/hannah_montana_2.png" "$CHROOT/usr/share/ubiquity/pixmaps/sc_2.png"
cp "$DATA_DIR/wallpapers/hannah_montana_3.png" "$CHROOT/usr/share/ubiquity/pixmaps/sc_3.png"

# Migrate KDE configs to Trinity
KDE_SRC=$(find "$TEMP_EXTRACT" -type d -name ".kde" | head -n 1)
[ -n "$KDE_SRC" ] && cp -r "$KDE_SRC/." "$CHROOT/etc/skel/.trinity/"

rm -rf "$TEMP_EXTRACT"

# --- 5. Identity & Bashrc Alias ---
echo "Writing Identity and Bashrc (Screenfetch Alias)..."

cat <<EOF > "$CHROOT/etc/lsb-release"
DISTRIB_ID=HMLR
DISTRIB_RELEASE=2026.1
DISTRIB_CODENAME=$UBUNTU_CODENAME
DISTRIB_DESCRIPTION="$HMLR_NAME"
EOF

cat <<EOF > "$CHROOT/etc/os-release"
PRETTY_NAME="$HMLR_NAME (24.04 LTS)"
NAME="$HMLR_NAME"
ID=hmlr
ID_LIKE=ubuntu
LOGO=hannah-montana-logo
EOF
cp "$CHROOT/etc/os-release" "$CHROOT/usr/lib/os-release"

# Auto-run screenfetch on terminal open
echo "alias ls='ls --color=auto'" >> "$CHROOT/etc/skel/.bashrc"
echo "screenfetch" >> "$CHROOT/etc/skel/.bashrc"

cat <<EOF > "$CHROOT/etc/casper.conf"
export USERNAME="hannah"
export USERFULLNAME="Hannah Montana"
export HOST="hannah-pc"
EOF

echo "export UBUNTU_RELEASE='$HMLR_NAME'" > "$CHROOT/etc/default/ubiquity"

# --- 6. Dockerized Build ---
echo "Starting Docker Build (Forcing Noble Mode)..."

docker run --privileged --rm \
    -v "$BUILD_DIR:/build" \
    -v "$OUTPUT_DIR:/output" \
    -w /build \
    ubuntu:noble /bin/bash -c "
        apt-get update && \
        apt-get install -y live-build curl wget gnupg squashfs-tools xorriso isolinux ubiquity-casper casper && \
        
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

        mkdir -p config/archives
        echo 'deb http://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-r14.1.x noble main deps' > config/archives/trinity.list.chroot
        
        wget http://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-keyring.deb
        mkdir -p config/packages.chroot
        cp trinity-keyring.deb config/packages.chroot/

        mkdir -p config/package-lists
        echo 'tde-trinity tdm-trinity screenfetch ubiquity ubiquity-frontend-gtk casper network-manager xserver-xorg' > config/package-lists/hmlr.list.chroot

        lb clean && lb build || exit 1
        
        mv *.iso /output/hmlr-revived-$DATE_TAG.iso
    "

sudo rm -rf "$BUILD_DIR"
echo "Done! ISO is in your output folder."
