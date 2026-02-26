#!/bin/bash

# --- 1. Paths & Configuration ---
BASE_DIR=$(pwd)
SOURCE_DIR="$BASE_DIR"
BUILD_DIR="$(pwd)/../../build"
OUTPUT_DIR="$(pwd)/../../output"
DATA_DIR="$(pwd)/../original_hml_data"
DATE_TAG=$(date +%Y%m%d)

HMLR_NAME="Hannah Montana Linux Revived"
UBUNTU_CODENAME="noble"

# --- 2. Staging & Permission Cleanup ---
echo "Cleaning and staging build environment..."
sudo rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
[ -d "$SOURCE_DIR" ] && cp -r "$SOURCE_DIR/." "$BUILD_DIR/"

CHROOT="$BUILD_DIR/config/includes.chroot"
mkdir -p "$CHROOT/etc/skel/.trinity/share/config" \
         "$CHROOT/opt/trinity/share/apps/kdm/themes" \
         "$CHROOT/opt/trinity/share/icons" \
         "$CHROOT/usr/share/wallpapers" \
         "$CHROOT/usr/share/pixmaps" \
         "$CHROOT/usr/lib" \
         "$CHROOT/etc/default" \
         "$CHROOT/usr/share/ubiquity/pixmaps"

# --- 3. IDENTITY & BRANDING ---
echo "Writing OS Identity (os-release & lsb-release)..."

cat <<EOF > "$CHROOT/etc/lsb-release"
DISTRIB_ID=HMLR
DISTRIB_RELEASE=2026.1
DISTRIB_CODENAME=$UBUNTU_CODENAME
DISTRIB_DESCRIPTION="$HMLR_NAME"
EOF

cat <<EOF > "$CHROOT/etc/os-release"
PRETTY_NAME="$HMLR_NAME"
NAME="$HMLR_NAME"
ID=hmlr
ID_LIKE=ubuntu
LOGO=hannah-montana-logo
EOF
cp "$CHROOT/etc/os-release" "$CHROOT/usr/lib/os-release"

# --- 4. ASSET MAPPING (Applying the Hannah Theme) ---
echo "Extracting and Mapping Hannah Montana Assets..."

# Use a temporary area to unpack your data archives
TEMP_ASSETS=$(mktemp -d)
tar -xJf "$DATA_DIR/icons.tar.xz" -C "$TEMP_ASSETS/" 2>/dev/null
tar -xzf "$DATA_DIR/skel.tar.gz" -C "$TEMP_ASSETS/" 2>/dev/null

# Move Icons and KDM themes to Trinity system paths
# (Adjusting paths based on typical HML data structure)
find "$TEMP_ASSETS" -type d -name "hannah_montana" -path "*/icons/*" -exec cp -r {} "$CHROOT/opt/trinity/share/icons/" \;
find "$TEMP_ASSETS" -type d -name "hannah_montana" -path "*/kdm/themes/*" -exec cp -r {} "$CHROOT/opt/trinity/share/apps/kdm/themes/" \;

# Wallpapers for System and Installer
cp "$DATA_DIR/wallpapers/hannah_montana_1.png" "$CHROOT/usr/share/wallpapers/hmlr_default.png"
cp "$DATA_DIR/wallpapers/hannah_montana_1.png" "$CHROOT/usr/share/pixmaps/hannah-montana-logo.png"
cp "$DATA_DIR/wallpapers/hannah_montana_1.png" "$CHROOT/usr/share/ubiquity/pixmaps/sc_1.png"
cp "$DATA_DIR/wallpapers/hannah_montana_2.png" "$CHROOT/usr/share/ubiquity/pixmaps/sc_2.png"
cp "$DATA_DIR/wallpapers/hannah_montana_3.png" "$CHROOT/usr/share/ubiquity/pixmaps/sc_3.png"

# Force the Trinity desktop to use the HML wallpaper
cat <<EOF > "$CHROOT/etc/skel/.trinity/share/config/kickerrc"
[Background]
Wallpaper=/usr/share/wallpapers/hmlr_default.png
WallpaperMode=Scaled
EOF

# Restore original .kde/skel settings if they exist
KDE_SKEL=$(find "$TEMP_ASSETS" -type d -name ".kde" | head -n 1)
[ -n "$KDE_SKEL" ] && cp -r "$KDE_SKEL/." "$CHROOT/etc/skel/.trinity/"

rm -rf "$TEMP_ASSETS"

# Screenfetch and Ubiquity setup
echo "screenfetch" >> "$CHROOT/etc/skel/.bashrc"
echo "export UBUNTU_RELEASE='$HMLR_NAME'" > "$CHROOT/etc/default/ubiquity"

# --- 5. DOCKERIZED BUILD (GPG & PACKAGE FIX) ---
echo "Starting Docker Build (Addressing GPG NO_PUBKEY)..."



docker run --privileged --rm \
    -v "$BUILD_DIR:/build" \
    -v "$OUTPUT_DIR:/output" \
    -w /build \
    ubuntu:noble /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update && apt-get install -y live-build curl wget gnupg squashfs-tools xorriso isolinux ubiquity-casper casper && \
        
        # 1. Trinity Repository Configuration
        mkdir -p config/archives
        REPO_LINE='deb http://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-r14.1.x noble main deps'
        echo \"\$REPO_LINE\" > config/archives/trinity.list.chroot
        echo \"\$REPO_LINE\" > config/archives/trinity.list.binary
        
        # 2. NUCLEAR GPG FIX: Inject key directly into the build's trusted store
        # This prevents the 'Not Signed' error by trusting the key before 'apt update' runs
        wget -qO- 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xC93AF1698685AD8B' | gpg --dearmor > config/archives/trinity.key.chroot
        cp config/archives/trinity.key.chroot config/archives/trinity.key.binary

        # 3. Live-Build Configuration
        lb config \
            --mode ubuntu \
            --distribution $UBUNTU_CODENAME \
            --parent-distribution $UBUNTU_CODENAME \
            --parent-mirror-binary http://archive.ubuntu.com/ubuntu/ \
            --architectures amd64 \
            --binary-images iso-hybrid \
            --iso-application 'HMLR' \
            --archive-areas 'main restricted universe multiverse'

        # 4. Final Package List (Including VLC)
        mkdir -p config/package-lists
        echo 'kubuntu-default-settings-trinity kubuntu-desktop-trinity screenfetch vlc ubiquity ubiquity-frontend-gtk network-manager xserver-xorg' > config/package-lists/hmlr.list.chroot

        # 5. Build Execution
        lb clean && lb build
        
        # 6. Result Verification
        if ls *.iso 1> /dev/null 2>&1; then
            mv *.iso /output/hmlr-revived-$DATE_TAG.iso
            echo 'SUCCESS: ISO CREATED'
        else
            echo 'FATAL ERROR: ISO build failed. Check logs above.'
            exit 1
        fi
    "

sudo rm -rf "$BUILD_DIR"
echo "Process Complete! Your Hannah Montana Linux Revived ISO is in the output folder."
