#!/bin/bash

# --- 1. Configuration & Paths ---
SOURCE_DIR="ubuntu-lts"
BUILD_DIR="../build"
OUTPUT_DIR="../output"
DATA_DIR="original_hml_data"
DATE_TAG=$(date +%Y%m%d)

# Branding Variables
HMLR_NAME="Hannah Montana Linux Revived"
HMLR_VER="2026.1"
UBUNTU_VER="24.04.4"
UBUNTU_CODENAME="noble"

# --- 2. Staging & Clean Slating ---
echo "Staging environment in $BUILD_DIR..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

# Copy base live-build structure from source to build folder
if [ -d "$SOURCE_DIR" ]; then cp -r "$SOURCE_DIR/." "$BUILD_DIR/"; fi

# Define the CHROOT root for easier coding
CHROOT="$BUILD_DIR/config/includes.chroot"
mkdir -p "$CHROOT/etc/skel/.trinity/share/config"
mkdir -p "$CHROOT/opt/trinity/share/apps/kdm/themes"
mkdir -p "$CHROOT/opt/trinity/share/apps/ksplash/Themes"
mkdir -p "$CHROOT/opt/trinity/share/icons"
mkdir -p "$CHROOT/opt/trinity/share/wallpapers"
mkdir -p "$CHROOT/usr/share/pixmaps"
mkdir -p "$CHROOT/usr/lib"
mkdir -p "$CHROOT/etc/fastfetch"

# --- 3. Asset Extraction & Trinity Mapping ---
echo "Extracting and re-mapping assets for Trinity..."
TEMP_EXTRACT=$(mktemp -d)

tar -xJf "$DATA_DIR/icons.tar.xz" -C "$TEMP_EXTRACT/"
tar -xzf "$DATA_DIR/skel.tar.gz" -C "$TEMP_EXTRACT/"

# Set Permissions (755) as requested
chmod -R 755 "$TEMP_EXTRACT"

# Map to Trinity Paths
cp -r "$TEMP_EXTRACT/hannah_montana" "$CHROOT/opt/trinity/share/icons/"
cp -r "$TEMP_EXTRACT/kdm/themes/hannah_montana" "$CHROOT/opt/trinity/share/apps/kdm/themes/"
cp -r "$TEMP_EXTRACT/ksplash/Themes/hannah_montana" "$CHROOT/opt/trinity/share/apps/ksplash/Themes/"
cp -r "$TEMP_EXTRACT/wallpapers/." "$CHROOT/opt/trinity/share/wallpapers/"

# Rice/Configs: Moving .kde content into .trinity
if [ -d "$TEMP_EXTRACT/.kde" ]; then
    cp -r "$TEMP_EXTRACT/.kde/." "$CHROOT/etc/skel/.trinity/"
fi

# Inject System Logo
if [ -f "$DATA_DIR/wallpapers/hannah_montana_1.png" ]; then
    cp "$DATA_DIR/wallpapers/hannah_montana_1.png" "$CHROOT/usr/share/pixmaps/hannah-montana-logo.png"
    chmod 644 "$CHROOT/usr/share/pixmaps/hannah-montana-logo.png"
fi

rm -rf "$TEMP_EXTRACT"

# --- 4. Branding (OS-Release, LSB, and Fastfetch) ---
echo "Applying Purple Branding and System Configuration..."

# OS-Release
cat <<EOF > "$CHROOT/etc/os-release"
PRETTY_NAME="$HMLR_NAME ($UBUNTU_VER LTS)"
NAME="$HMLR_NAME"
VERSION_ID="$UBUNTU_VER"
VERSION="$UBUNTU_VER (Noble Numbat)"
ID=hmlr
ID_LIKE=ubuntu
VERSION_CODENAME=$UBUNTU_CODENAME
LOGO=hannah-montana-logo
HOME_URL="https://github.com/techtimefor/hmlr"
EOF
cp "$CHROOT/etc/os-release" "$CHROOT/usr/lib/os-release"

# LSB-Release
cat <<EOF > "$CHROOT/etc/lsb-release"
DISTRIB_ID=HMLR
DISTRIB_RELEASE=$UBUNTU_VER
DISTRIB_CODENAME=$UBUNTU_CODENAME
DISTRIB_DESCRIPTION="$HMLR_NAME $HMLR_VER"
EOF

# Purple Fastfetch Config
cat <<EOF > "$CHROOT/etc/fastfetch/config.jsonc"
{
    "\$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "type": "builtin",
        "source": "ubuntu",
        "color": { "1": "magenta", "2": "magenta" }
    },
    "display": { "color": "magenta" },
    "modules": [
        "title",
        "separator",
        { "type": "os", "key": "Distro ", "keyColor": "magenta" },
        { "type": "de", "key": "Desktop", "keyColor": "magenta" },
        "uptime",
        "packages",
        "memory"
    ]
}
EOF

# --- 5. Trinity Repository & Package Lists ---
mkdir -p "$BUILD_DIR/config/archives"
cat <<EOF > "$BUILD_DIR/config/archives/trinity.list.chroot"
deb http://mirror.ppa.trinitydesktop.org/trinity/deb/noble noble main
deb http://mirror.ppa.trinitydesktop.org/trinity/deb/noble-deps noble main
EOF

mkdir -p "$BUILD_DIR/config/package-lists"
cat <<EOF > "$BUILD_DIR/config/package-lists/hmlr.list.chroot"
tde-trinity
tdm-trinity
tkgoodies-trinity
fastfetch
xorriso
squashfs-tools
isolinux
EOF

# --- 6. Dockerized ISO Build ---
echo "Starting Docker Build (this will take time)..."
docker run --privileged --rm \
    -v "$(pwd)/$BUILD_DIR:/build" \
    -v "$(pwd)/$OUTPUT_DIR:/output" \
    -w /build \
    ubuntu:noble /bin/bash -c "
        apt-get update && \
        apt-get install -y live-build curl wget gnupg squashfs-tools xorriso isolinux && \
        # Handle Trinity Keyring inside the build environment
        wget http://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-keyring.deb && \
        mkdir -p config/packages.chroot && \
        cp trinity-keyring.deb config/packages.chroot/ && \
        # Standard live-build process
        lb clean && \
        lb config --binary-images iso-hybrid --iso-application 'HMLR_Ubuntu' --iso-publisher 'TechTimeFor' && \
        lb build && \
        mv *.iso /output/hmlr-ubuntu-noble-$DATE_TAG.iso"

# --- 7. Cleanup (The Yeet) ---
echo "ISO Build Complete. Cleaning up build folder..."
rm -rf "$BUILD_DIR"

echo "Done! Find your ISO in $OUTPUT_DIR"
