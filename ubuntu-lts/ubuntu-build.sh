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

# --- 2. Staging ---
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

# --- 3. IDENTITY & BRANDING (OS-Release) ---
echo "Writing OS Identity..."

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

# --- 4. ASSET MAPPING (The Hannah Customization) ---
echo "Mapping Hannah Montana Assets..."

TEMP_ASSETS=$(mktemp -d)
tar -xJf "$DATA_DIR/icons.tar.xz" -C "$TEMP_ASSETS/" 2>/dev/null
tar -xzf "$DATA_DIR/skel.tar.gz" -C "$TEMP_ASSETS/" 2>/dev/null

# Map Icons and KDM Themes
find "$TEMP_ASSETS" -type d -name "hannah_montana" -path "*/icons/*" -exec cp -r {} "$CHROOT/opt/trinity/share/icons/" \;
find "$TEMP_ASSETS" -type d -name "hannah_montana" -path "*/kdm/themes/*" -exec cp -r {} "$CHROOT/opt/trinity/share/apps/kdm/themes/" \;

# Wallpapers
cp "$DATA_DIR/wallpapers/hannah_montana_1.png" "$CHROOT/usr/share/wallpapers/hmlr_default.png"
cp "$DATA_DIR/wallpapers/hannah_montana_1.png" "$CHROOT/usr/share/pixmaps/hannah-montana-logo.png"
cp "$DATA_DIR/wallpapers/hannah_montana_1.png" "$CHROOT/usr/share/ubiquity/pixmaps/sc_1.png"
cp "$DATA_DIR/wallpapers/hannah_montana_2.png" "$CHROOT/usr/share/ubiquity/pixmaps/sc_2.png"
cp "$DATA_DIR/wallpapers/hannah_montana_3.png" "$CHROOT/usr/share/ubiquity/pixmaps/sc_3.png"

# Force Wallpaper in Trinity Config
cat <<EOF > "$CHROOT/etc/skel/.trinity/share/config/kickerrc"
[Background]
Wallpaper=/usr/share/wallpapers/hmlr_default.png
WallpaperMode=Scaled
EOF

rm -rf "$TEMP_ASSETS"

# Extras
echo "screenfetch" >> "$CHROOT/etc/skel/.bashrc"
echo "export UBUNTU_RELEASE='$HMLR_NAME'" > "$CHROOT/etc/default/ubiquity"

# --- 5. DOCKERIZED BUILD (Bootloader Bypass) ---
echo "Starting Docker Build..."

docker run --privileged --rm \
    -v "$(pwd)/../../build:/build" \
    -v "$(pwd)/../../output:/output" \
    -w /build \
    ubuntu:noble /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        export PATH=\$PATH:/usr/bin:/usr/sbin:/bin:/sbin
        
        # 1. Install EVERYTHING up front
        apt-get update && apt-get install -y \
            live-build curl wget gnupg squashfs-tools xorriso \
            syslinux-utils syslinux-common isolinux \
            mtools dosfstools
        
        # 2. Force the tool paths (The fix for 'isohybrid not found')
        ln -sf /usr/bin/isohybrid /usr/local/bin/isohybrid
        ln -sf /usr/bin/isohybrid /bin/isohybrid

        # 3. TRINITY REPO SETUP
        mkdir -p config/archives
        echo 'deb http://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-r14.1.x noble main deps' > config/archives/trinity.list.chroot
        wget -qO- 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xC93AF1698685AD8B' | gpg --dearmor > config/archives/trinity.key.chroot
        cp config/archives/trinity.key.chroot config/archives/trinity.key.binary

        # 4. CONFIG (Using isolinux for guaranteed hybridization)
        lb config \
            --mode ubuntu \
            --distribution noble \
            --architectures amd64 \
            --binary-images iso-hybrid \
            --bootloader isolinux \
            --archive-areas 'main restricted universe multiverse' \
            --iso-application 'HMLR_REVIVED' \
            --iso-volume 'HMLR_2026'

        # 5. PACKAGE LIST
        mkdir -p config/package-lists
        echo 'kubuntu-default-settings-trinity kubuntu-desktop-trinity vlc screenfetch ubiquity' > config/package-lists/hmlr.list.chroot

        # 6. THE BUILD
        lb clean --purge
        lb build

        # 7. EXPORT (Check both locations)
        if ls *.iso 1> /dev/null 2>&1; then
            mv *.iso /output/hmlr-revived.iso
            echo 'SUCCESS: ISO EXPORTED'
        elif [ -f chroot/binary.hybrid.iso ]; then
            mv chroot/binary.hybrid.iso /output/hmlr-revived.iso
            echo 'SUCCESS: ISO RESCUED FROM CHROOT'
        else
            echo 'FATAL ERROR: Build failed'
            exit 1
        fi
    "

sudo rm -rf "$BUILD_DIR"
