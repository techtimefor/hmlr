#!/bin/bash

# --- 1. Paths ---
BASE_DIR=$(pwd)
SOURCE_DIR="$BASE_DIR"
BUILD_DIR="$(pwd)/../../build"
OUTPUT_DIR="$(pwd)/../../output"
DATA_DIR="$(pwd)/../original_hml_data"
DATE_TAG=$(date +%Y%m%d)

# Branding
HMLR_NAME="Hannah Montana Linux Revived"
UBUNTU_CODENAME="noble"

# --- 2. Staging ---
echo "Cleaning and staging build environment..."
sudo rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
[ -d "$SOURCE_DIR" ] && cp -r "$SOURCE_DIR/." "$BUILD_DIR/"

CHROOT="$BUILD_DIR/config/includes.chroot"
# Create the specific Trinity theme paths
mkdir -p "$CHROOT/opt/trinity/share/icons" \
         "$CHROOT/opt/trinity/share/apps/kdm/themes" \
         "$CHROOT/opt/trinity/share/wallpapers" \
         "$CHROOT/etc/skel/.trinity/share/config" \
         "$CHROOT/usr/share/pixmaps" \
         "$CHROOT/usr/lib"

# --- 3. THE CUSTOMIZATION (Mapping your data) ---
echo "Applying Hannah Montana Themes and Branding..."

# 1. Unpack your assets to a temp folder to move them
TEMP_ASSETS=$(mktemp -d)
tar -xJf "$DATA_DIR/icons.tar.xz" -C "$TEMP_ASSETS/"
tar -xzf "$DATA_DIR/skel.tar.gz" -C "$TEMP_ASSETS/"

# 2. Move Icons (Assuming folder name inside tar is 'hannah_montana')
cp -r "$TEMP_ASSETS/icons/hannah_montana" "$CHROOT/opt/trinity/share/icons/" 2>/dev/null

# 3. Move KDM Theme (The login screen)
cp -r "$TEMP_ASSETS/kdm/hannah_montana" "$CHROOT/opt/trinity/share/apps/kdm/themes/" 2>/dev/null

# 4. Set the Global Wallpaper
cp "$DATA_DIR/wallpapers/hannah_montana_1.png" "$CHROOT/opt/trinity/share/wallpapers/hannah-default.png"
cp "$DATA_DIR/wallpapers/hannah_montana_1.png" "$CHROOT/usr/share/pixmaps/hannah-montana-logo.png"

# 5. Force Trinity to use the Pink Theme & Wallpaper
cat <<EOF > "$CHROOT/etc/skel/.trinity/share/config/kdeglobals"
[General]
desktopFont=Sans Serif,9,-1,5,50,0,0,0,0,0
Theme=hannah_montana
colorScheme=hannah_montana.kcsrc

[Icons]
Theme=hannah_montana
EOF

cat <<EOF > "$CHROOT/etc/skel/.trinity/share/config/kickerrc"
[Background]
Wallpaper=/opt/trinity/share/wallpapers/hannah-default.png
WallpaperMode=Scaled
EOF

rm -rf "$TEMP_ASSETS"

# --- 4. OS Identity (For Screenfetch) ---
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

echo "screenfetch" >> "$CHROOT/etc/skel/.bashrc"

# --- 5. Dockerized Build ---
echo "Building ISO..."


docker run --privileged --rm \
    -v "$BUILD_DIR:/build" \
    -v "$OUTPUT_DIR:/output" \
    -w /build \
    ubuntu:noble /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update && apt-get install -y live-build curl wget gnupg squashfs-tools xorriso isolinux ubiquity-casper casper && \
        
        mkdir -p config/archives
        echo 'deb http://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-r14.1.x noble main deps' > config/archives/trinity.list.chroot
        
        # GPG NUCLEAR FIX
        wget -qO- 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xC93AF1698685AD8B' | gpg --dearmor > config/archives/trinity.key.chroot

        lb config \
            --mode ubuntu \
            --distribution $UBUNTU_CODENAME \
            --architectures amd64 \
            --bootstrap-qemu-static true \
            --archive-areas 'main restricted universe multiverse'

        mkdir -p config/package-lists
        echo 'tde-trinity kubuntu-default-settings-trinity screenfetch vlc' > config/package-lists/hmlr.list.chroot

        lb clean && lb build
        
        [ -f *.iso ] && mv *.iso /output/hmlr-revived-$DATE_TAG.iso || exit 1
    "

# Cleanup only if successful (or change to always cleanup)
sudo rm -rf "$BUILD_DIR"
