#!/bin/bash

# --- 1. Configuration ---
SOURCE_DIR="ubuntu-lts"
BUILD_DIR="$(pwd)/../build"
OUTPUT_DIR="$(pwd)/../output"
DATA_DIR="$(pwd)/original_hml_data"
DATE_TAG=$(date +%Y%m%d)

# Branding Variables
HMLR_NAME="Hannah Montana Linux Revived"
HMLR_VER="2026.1"
UBUNTU_VER="24.04.4"
UBUNTU_CODENAME="noble"

# --- 2. Clean Staging Area ---
echo "Cleaning staging area (Sudo required for Docker cleanup)..."
sudo rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# Copy base structure
[ -d "$SOURCE_DIR" ] && cp -r "$SOURCE_DIR/." "$BUILD_DIR/"

CHROOT="$BUILD_DIR/config/includes.chroot"
mkdir -p "$CHROOT/etc"
mkdir -p "$CHROOT/etc/skel/.trinity/share/config"
mkdir -p "$CHROOT/opt/trinity/share/apps/kdm/themes"
mkdir -p "$CHROOT/opt/trinity/share/icons"
mkdir -p "$CHROOT/usr/share/pixmaps"
mkdir -p "$CHROOT/etc/fastfetch"
mkdir -p "$CHROOT/usr/lib"

# --- 3. Asset Extraction & Trinity Mapping ---
echo "Extracting Purple Assets..."
TEMP_EXTRACT=$(mktemp -d)
tar -xJf "$DATA_DIR/icons.tar.xz" -C "$TEMP_EXTRACT/"
tar -xzf "$DATA_DIR/skel.tar.gz" -C "$TEMP_EXTRACT/"

# Map using find to ensure we catch folders regardless of archive structure
find "$TEMP_EXTRACT" -type d -name "hannah_montana" -path "*/icons/*" -exec cp -r {} "$CHROOT/opt/trinity/share/icons/" \;
find "$TEMP_EXTRACT" -type d -name "hannah_montana" -path "*/kdm/themes/*" -exec cp -r {} "$CHROOT/opt/trinity/share/apps/kdm/themes/" \;
find "$TEMP_EXTRACT" -name "hannah_montana_1.png" -exec cp {} "$CHROOT/usr/share/pixmaps/hannah-montana-logo.png" \;

# Config Migration (.kde -> .trinity)
KDE_SRC=$(find "$TEMP_EXTRACT" -type d -name ".kde" | head -n 1)
[ -n "$KDE_SRC" ] && cp -r "$KDE_SRC/." "$CHROOT/etc/skel/.trinity/"

rm -rf "$TEMP_EXTRACT"

# --- 4. Branding (OS-Release, LSB, Installer) ---
echo "Writing Identity files (lsb-release, casper, fastfetch)..."

# LSB-Release (Fixes the 'Missing' issue)
cat <<EOF > "$CHROOT/etc/lsb-release"
DISTRIB_ID=HMLR
DISTRIB_RELEASE=$UBUNTU_VER
DISTRIB_CODENAME=$UBUNTU_CODENAME
DISTRIB_DESCRIPTION="$HMLR_NAME"
EOF

# OS-Release
cat <<EOF > "$CHROOT/etc/os-release"
PRETTY_NAME="$HMLR_NAME ($UBUNTU_VER LTS)"
NAME="$HMLR_NAME"
VERSION_ID="$UBUNTU_VER"
ID=hmlr
ID_LIKE=ubuntu
LOGO=hannah-montana-logo
EOF
cp "$CHROOT/etc/os-release" "$CHROOT/usr/lib/os-release"

# Live User Configuration (Casper)
cat <<EOF > "$CHROOT/etc/casper.conf"
export USERNAME="hannah"
export USERFULLNAME="Hannah Montana"
export HOST="hannah-montana-pc"
export BUILD_SYSTEM="Ubuntu"
EOF

# Fastfetch (Purple override)
cat <<EOF > "$CHROOT/etc/fastfetch/config.jsonc"
{
    "logo": { "type": "builtin", "source": "ubuntu", "color": { "1": "magenta", "2": "magenta" } },
    "display": { "color": "magenta" },
    "modules": [ "title", "separator", "os", "de", "uptime", "packages", "memory" ]
}
EOF

# --- 5. Installer Configuration (Ubiquity Seeding) ---
mkdir -p "$CHROOT/etc/default"
cat <<EOF > "$CHROOT/etc/default/ubiquity"
# Custom Branding for HMLR
export UBUNTU_RELEASE="$HMLR_NAME"
EOF

# --- 6. Dockerized ISO Build ---
echo "Starting Docker Build for Noble..."
docker run --privileged --rm \
    -v "$BUILD_DIR:/build" \
    -v "$OUTPUT_DIR:/output" \
    -w /build \
    ubuntu:noble /bin/bash -c "
        apt-get update && \
        apt-get install -y live-build curl wget gnupg squashfs-tools xorriso isolinux ubiquity-casper casper && \
        
        # 1. Trinity Keyring Setup
        wget http://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-keyring.deb && \
        mkdir -p config/packages.chroot && \
        cp trinity-keyring.deb config/packages.chroot/ && \

        # 2. lb config - Explicitly setting Ubuntu Mode
        lb config \
            --mode ubuntu \
            --distribution $UBUNTU_CODENAME \
            --parent-distribution $UBUNTU_CODENAME \
            --parent-mirror-binary http://archive.ubuntu.com/ubuntu/ \
            --mirror-binary http://archive.ubuntu.com/ubuntu/ \
            --architectures amd64 \
            --linux-flavours generic \
            --binary-images iso-hybrid \
            --iso-application '$HMLR_NAME' \
            --iso-publisher 'TechTimeFor' \
            --bootloader syslinux \
            --archive-areas 'main restricted universe multiverse'

        # 3. Inject Trinity Repos
        mkdir -p config/archives
        echo 'deb http://mirror.ppa.trinitydesktop.org/trinity/deb/noble noble main' > config/archives/trinity.list.chroot
        echo 'deb http://mirror.ppa.trinitydesktop.org/trinity/deb/noble-deps noble main' >> config/archives/trinity.list.chroot

        # 4. Final Package List (Everything needed for a working desktop)
        mkdir -p config/package-lists
        echo 'tde-trinity tdm-trinity fastfetch ubiquity ubiquity-frontend-gtk casper network-manager' > config/package-lists/hmlr.list.chroot

        # 5. Execute Build
        lb clean && lb build
        
        # 6. Export result
        mv *.iso /output/hmlr-ubuntu-noble-$DATE_TAG.iso
    "

# --- 7. Final Cleanup ---
sudo rm -rf "$BUILD_DIR"
echo "Build Successful! ISO moved to ../output"
