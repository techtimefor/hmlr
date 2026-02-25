#!/bin/bash

# --- 1. Configuration & Absolute Paths ---
BASE_DIR=$(pwd)
SOURCE_DIR="$BASE_DIR/ubuntu-lts"
BUILD_DIR="$BASE_DIR/../build"
OUTPUT_DIR="$BASE_DIR/../output"
DATA_DIR="$BASE_DIR/original_hml_data"
DATE_TAG=$(date +%Y%m%d)

# Branding
HMLR_NAME="Hannah Montana Linux Revived"
UBUNTU_CODENAME="noble"

# --- 2. Staging & Permission Cleanup ---
echo "Cleaning staging area..."
sudo rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# Copy base structure if it exists
[ -d "$SOURCE_DIR" ] && cp -r "$SOURCE_DIR/." "$BUILD_DIR/"

CHROOT="$BUILD_DIR/config/includes.chroot"
mkdir -p "$CHROOT/etc/skel/.trinity/share/config" \
         "$CHROOT/opt/trinity/share/apps/kdm/themes" \
         "$CHROOT/opt/trinity/share/icons" \
         "$CHROOT/usr/share/pixmaps" \
         "$CHROOT/etc/default" \
         "$CHROOT/usr/share/ubiquity/pixmaps"

# --- 3. Asset Extraction & Mapping ---
echo "Extracting and Mapping Purple Assets..."
TEMP_EXTRACT=$(mktemp -d)

tar -xJf "$DATA_DIR/icons.tar.xz" -C "$TEMP_EXTRACT/"
tar -xzf "$DATA_DIR/skel.tar.gz" -C "$TEMP_EXTRACT/"

# Map themes and icons
find "$TEMP_EXTRACT" -type d -name "hannah_montana" -path "*/icons/*" -exec cp -r {} "$CHROOT/opt/trinity/share/icons/" \;
find "$TEMP_EXTRACT" -type d -name "hannah_montana" -path "*/kdm/themes/*" -exec cp -r {} "$CHROOT/opt/trinity/share/apps/kdm/themes/" \;
cp "$DATA_DIR/wallpapers/hannah_montana_1.png" "$CHROOT/usr/share/pixmaps/hannah-montana-logo.png"

# Installer Slideshow (Ubiquity)
echo "Setting up Installer Slideshow..."
# Map the wallpapers you provided to the installer background rotation
cp "$DATA_DIR/wallpapers/hannah_montana_1.png" "$CHROOT/usr/share/ubiquity/pixmaps/sc_1.png"
cp "$DATA_DIR/wallpapers/hannah_montana_2.png" "$CHROOT/usr/share/ubiquity/pixmaps/sc_2.png"
cp "$DATA_DIR/wallpapers/hannah_montana_3.png" "$CHROOT/usr/share/ubiquity/pixmaps/sc_3.png"

# Migrate KDE configs to Trinity
KDE_SRC=$(find "$TEMP_EXTRACT" -type d -name ".kde" | head -n 1)
[ -n "$KDE_SRC" ] && cp -r "$KDE_SRC/." "$CHROOT/etc/skel/.trinity/"

rm -rf "$TEMP_EXTRACT"

# --- 4. System Identity & Installer Setup ---
echo "Writing LSB-Release and Ubiquity Configs..."

cat <<EOF > "$CHROOT/etc/lsb-release"
DISTRIB_ID=HMLR
DISTRIB_RELEASE=24.04
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

cat <<EOF > "$CHROOT/etc/casper.conf"
export USERNAME="hannah"
export USERFULLNAME="Hannah Montana"
export HOST="hannah-pc"
EOF

# Branding the Installer
echo "export UBUNTU_RELEASE='$HMLR_NAME'" > "$CHROOT/etc/default/ubiquity"

# --- 5. Dockerized Build ---
echo "Starting Docker Build..."

docker run --privileged --rm \
    -v "$BUILD_DIR:/build" \
    -v "$OUTPUT_DIR:/output" \
    -v "$DATA_DIR:/data" \
    -w /build \
    ubuntu:noble /bin/bash -c "
        apt-get update && \
        apt-get install -y live-build curl wget gnupg squashfs-tools xorriso isolinux ubiquity-casper casper && \
        
        # 1. lb config (FORCING UBUNTU MODE)
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

        # 2. Add Trinity R14.1.x Repository
        mkdir -p config/archives
        echo 'deb http://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-r14.1.x noble main deps' > config/archives/trinity.list.chroot
        
        # Keyring Setup
        wget http://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-keyring.deb
        mkdir -p config/packages.chroot
        cp trinity-keyring.deb config/packages.chroot/

        # 3. Define Package List (SCREENFETCH INCLUDED)
        mkdir -p config/package-lists
        echo 'tde-trinity tdm-trinity screenfetch fastfetch ubiquity ubiquity-frontend-gtk casper network-manager xserver-xorg' > config/package-lists/hmlr.list.chroot

        # 4. Build the ISO
        lb clean && lb build || exit 1
        
        # 5. Export ISO
        mv *.iso /output/hmlr-noble-$DATE_TAG.iso
    "

# --- 6. Cleanup ---
sudo rm -rf "$BUILD_DIR"
echo "Done! check your output folder for the ISO."
