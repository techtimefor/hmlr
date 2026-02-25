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

# --- 2. Sanity Checks ---
if ! command -v docker &> /dev/null; then
    echo "ERROR: 'docker' command not found. Please install docker or run 'sudo apt install docker.io'."
    exit 1
fi

# --- 3. Clean Staging Area ---
echo "Staging environment in $BUILD_DIR..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

if [ -d "$SOURCE_DIR" ]; then cp -r "$SOURCE_DIR/." "$BUILD_DIR/"; fi

CHROOT="$BUILD_DIR/config/includes.chroot"
mkdir -p "$CHROOT/etc/skel/.trinity/share/config"
mkdir -p "$CHROOT/opt/trinity/share/apps/kdm/themes"
mkdir -p "$CHROOT/opt/trinity/share/apps/ksplash/Themes"
mkdir -p "$CHROOT/opt/trinity/share/icons"
mkdir -p "$CHROOT/opt/trinity/share/wallpapers"
mkdir -p "$CHROOT/usr/share/pixmaps"
mkdir -p "$CHROOT/usr/lib"
mkdir -p "$CHROOT/etc/fastfetch"

# --- 4. Asset Extraction & Smart Mapping ---
echo "Extracting and re-mapping assets for Trinity..."
TEMP_EXTRACT=$(mktemp -d)

# Unpack everything to the temp dir
tar -xJf "$DATA_DIR/icons.tar.xz" -C "$TEMP_EXTRACT/"
tar -xzf "$DATA_DIR/skel.tar.gz" -C "$TEMP_EXTRACT/"
chmod -R 755 "$TEMP_EXTRACT"

# SMART FIND: Search for the folders instead of assuming path
echo "Locating hannah_montana asset folders..."

# Find and copy Icons
find "$TEMP_EXTRACT" -type d -name "hannah_montana" -path "*/icons/*" -exec cp -r {} "$CHROOT/opt/trinity/share/icons/" \;

# Find and copy KDM Theme
find "$TEMP_EXTRACT" -type d -name "hannah_montana" -path "*/kdm/themes/*" -exec cp -r {} "$CHROOT/opt/trinity/share/apps/kdm/themes/" \;

# Find and copy KSplash Theme
find "$TEMP_EXTRACT" -type d -name "hannah_montana" -path "*/ksplash/*" -exec cp -r {} "$CHROOT/opt/trinity/share/apps/ksplash/Themes/" \;

# Find Wallpapers (Look for any .png or .jpg in a wallpaper folder)
find "$TEMP_EXTRACT" -type d -name "wallpapers" -exec cp -r {}/ "$CHROOT/opt/trinity/share/" \;

# Rice/Configs: Find .kde and merge it
KDE_DIR=$(find "$TEMP_EXTRACT" -type d -name ".kde" | head -n 1)
if [ -n "$KDE_DIR" ]; then
    cp -r "$KDE_DIR/." "$CHROOT/etc/skel/.trinity/"
fi

# Logo Injection (Checking common naming)
LOGO_SRC=$(find "$TEMP_EXTRACT" -name "hannah_montana_1.png" | head -n 1)
if [ -f "$LOGO_SRC" ]; then
    cp "$LOGO_SRC" "$CHROOT/usr/share/pixmaps/hannah-montana-logo.png"
    chmod 644 "$CHROOT/usr/share/pixmaps/hannah-montana-logo.png"
fi

rm -rf "$TEMP_EXTRACT"

# --- 5. Branding (OS-Release, LSB, Fastfetch) ---
echo "Applying Purple Branding..."

cat <<EOF > "$CHROOT/etc/os-release"
PRETTY_NAME="$HMLR_NAME ($UBUNTU_VER LTS)"
NAME="$HMLR_NAME"
VERSION_ID="$UBUNTU_VER"
ID=hmlr
ID_LIKE=ubuntu
LOGO=hannah-montana-logo
EOF
cp "$CHROOT/etc/os-release" "$CHROOT/usr/lib/os-release"

cat <<EOF > "$CHROOT/etc/lsb-release"
DISTRIB_ID=HMLR
DISTRIB_RELEASE=$UBUNTU_VER
DISTRIB_DESCRIPTION="$HMLR_NAME $HMLR_VER"
EOF

cat <<EOF > "$CHROOT/etc/fastfetch/config.jsonc"
{
    "\$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": { "type": "builtin", "source": "ubuntu", "color": { "1": "magenta", "2": "magenta" } },
    "display": { "color": "magenta" },
    "modules": [ "title", "separator", "os", "de", "uptime", "packages", "memory" ]
}
EOF

# --- 6. Repository & Package Lists ---
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

# --- 7. Docker Build ---
echo "Starting Docker Build..."
docker run --privileged --rm \
    -v "$(pwd)/$BUILD_DIR:/build" \
    -v "$(pwd)/$OUTPUT_DIR:/output" \
    -w /build \
    ubuntu:noble /bin/bash -c "
        apt-get update && \
        apt-get install -y live-build curl wget gnupg squashfs-tools xorriso isolinux && \
        wget http://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-keyring.deb && \
        mkdir -p config/packages.chroot && \
        cp trinity-keyring.deb config/packages.chroot/ && \
        lb clean && \
        lb config --binary-images iso-hybrid --iso-application 'HMLR' && \
        lb build && \
        mv *.iso /output/hmlr-ubuntu-$DATE_TAG.iso"

# --- 8. Cleanup ---
rm -rf "$BUILD_DIR"
echo "Done! ISO is in $OUTPUT_DIR"
