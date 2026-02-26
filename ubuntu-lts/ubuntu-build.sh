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

# --- 3. CUSTOMIZATION & THEME MAPPING ---
echo "Applying Hannah Montana Themes and Assets..."

# Identity Files (For Screenfetch logo/detection)
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

# Mapping Wallpapers (System and Installer)
cp "$DATA_DIR/wallpapers/hannah_montana_1.png" "$CHROOT/usr/share/wallpapers/hmlr_default.png"
cp "$DATA_DIR/wallpapers/hannah_montana_1.png" "$CHROOT/usr/share/pixmaps/hannah-montana-logo.png"
cp "$DATA_DIR/wallpapers/hannah_montana_1.png" "$CHROOT/usr/share/ubiquity/pixmaps/sc_1.png"
cp "$DATA_DIR/wallpapers/hannah_montana_2.png" "$CHROOT/usr/share/ubiquity/pixmaps/sc_2.png"
cp "$DATA_DIR/wallpapers/hannah_montana_3.png" "$CHROOT/usr/share/ubiquity/pixmaps/sc_3.png"

# Extracting Icons/Skel from your host data into the ISO
TEMP_ASSETS=$(mktemp -d)
tar -xJf "$DATA_DIR/icons.tar.xz" -C "$TEMP_ASSETS/" 2>/dev/null
tar -xzf "$DATA_DIR/skel.tar.gz" -C "$TEMP_ASSETS/" 2>/dev/null

# Move Icons and Themes to Trinity paths
[ -d "$TEMP_ASSETS/hannah_montana" ] && cp -r "$TEMP_ASSETS/hannah_montana" "$CHROOT/opt/trinity/share/icons/"
[ -d "$TEMP_ASSETS/.kde" ] && cp -r "$TEMP_ASSETS/.kde/." "$CHROOT/etc/skel/.trinity/"

# Force Wallpaper in Config
cat <<EOF > "$CHROOT/etc/skel/.trinity/share/config/kickerrc"
[Background]
Wallpaper=/usr/share/wallpapers/hmlr_default.png
WallpaperMode=Scaled
EOF

# Bash/Installer Extras
echo "screenfetch" >> "$CHROOT/etc/skel/.bashrc"
echo "export UBUNTU_RELEASE='$HMLR_NAME'" > "$CHROOT/etc/default/ubiquity"

rm -rf "$TEMP_ASSETS"

# --- 4. DOCKERIZED BUILD (The Engine) ---
echo "Starting Docker Build (Addressing GPG NO_PUBKEY)..."



docker run --privileged --rm \
    -v "$BUILD_DIR:/build" \
    -v "$OUTPUT_DIR:/output" \
    -w /build \
    ubuntu:noble /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update && apt-get install -y live-build curl wget gnupg squashfs-tools xorriso isolinux ubiquity-casper casper && \
        
        # Setup Trinity Repo
        mkdir -p config/archives
        REPO_LINE='deb http://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-r14.1.x noble main deps'
        echo \"\$REPO_LINE\" > config/archives/trinity.list.chroot
        echo \"\$REPO_LINE\" > config/archives/trinity.list.binary
        
        # THE GPG FIX: Inject key directly into build archive
        wget -qO- 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xC93AF1698685AD8B' | gpg --dearmor > config/archives/trinity.key.chroot
        cp config/archives/trinity.key.chroot config/archives/trinity.key.binary
        
        # Download Keyring .deb for local installation
        mkdir -p config/packages.chroot
        wget http://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-keyring.deb -O config/packages.chroot/trinity-keyring_all.deb

        # lb config
        lb config \
            --mode ubuntu \
            --distribution $UBUNTU_CODENAME \
            --parent-distribution $UBUNTU_CODENAME \
            --parent-mirror-binary http://archive.ubuntu.com/ubuntu/ \
            --architectures amd64 \
            --binary-images iso-hybrid \
            --iso-application 'HMLR' \
            --archive-areas 'main restricted universe multiverse'

        # Package List (Trinity + VLC + Screenfetch)
        mkdir -p config/package-lists
        echo 'kubuntu-default-settings-trinity kubuntu-desktop-trinity screenfetch vlc ubiquity ubiquity-frontend-gtk network-manager xserver-xorg' > config/package-lists/hmlr.list.chroot

        # Run the Build
        lb clean && lb build
        
        # Verify and Move Result
        if ls *.iso 1> /dev/null 2>&1; then
            mv *.iso /output/hmlr-revived-$DATE_TAG.iso
            echo 'SUCCESS: ISO EXPORTED TO OUTPUT FOLDER'
        else
            echo 'FATAL ERROR: ISO build failed. Check logs above for package errors.'
            exit 1
        fi
    "

sudo rm -rf "$BUILD_DIR"
