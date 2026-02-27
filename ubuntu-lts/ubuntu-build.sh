#!/bin/bash
# --- 1. Paths & Configuration ---
BASE_DIR=$(pwd)
SOURCE_DIR="$BASE_DIR"
BUILD_DIR="$(pwd)/../../build"
OUTPUT_DIR="$(pwd)/../../output"
DATA_DIR="$(pwd)/../original_hml_data"
HMLR_NAME="Hannah Montana Linux Revived"
UBUNTU_CODENAME="noble"

# --- 2. Staging ---
echo "Cleaning and staging build environment..."
sudo rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
[ -d "$SOURCE_DIR" ] && cp -r "$SOURCE_DIR/." "$BUILD_DIR/"

CHROOT="$BUILD_DIR/config/includes.chroot"
# Create all necessary paths for Trinity and Installer assets
mkdir -p "$CHROOT/etc/skel/.trinity/share/config" \
         "$CHROOT/opt/trinity/share/apps/kdm/themes" \
         "$CHROOT/usr/share/wallpapers" \
         "$CHROOT/usr/share/pixmaps" \
         "$CHROOT/usr/share/icons" \
         "$CHROOT/usr/share/sounds" \
         "$CHROOT/etc/default"

# --- 3. IDENTITY & BRANDING ---
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

# --- 4. ASSET MAPPING ---
echo "Mapping Hannah Montana Assets from GitHub data..."
TEMP_ASSETS=$(mktemp -d)
tar -xJf "$DATA_DIR/icons.tar.xz" -C "$TEMP_ASSETS/" 2>/dev/null
tar -xzf "$DATA_DIR/skel.tar.gz" -C "$TEMP_ASSETS/" 2>/dev/null

# Move Icons to the proper system path
find "$TEMP_ASSETS" -type d -name "hannah_montana" -path "*/icons/*" -exec cp -r {} "$CHROOT/usr/share/icons/" \;
# Move KDM Themes
find "$TEMP_ASSETS" -type d -name "hannah_montana" -path "*/kdm/themes/*" -exec cp -r {} "$CHROOT/opt/trinity/share/apps/kdm/themes/" \;

# Set Wallpapers
cp "$DATA_DIR/wallpapers/hannah_montana_1.png" "$CHROOT/usr/share/wallpapers/hmlr_default.png"
cp "$DATA_DIR/wallpapers/hannah_montana_1.png" "$CHROOT/usr/share/pixmaps/hannah-montana-logo.png"

# --- THE PURPLE PATCH: Force Trinity Config ---
# This fixes the "Vanilla" look by forcing the icons and wallpaper in the user template
cat <<EOF > "$CHROOT/etc/skel/.trinity/share/config/kdeglobals"
[Icons]
Theme=hannah_montana

[General]
Wallpaper=/usr/share/wallpapers/hmlr_default.png
WallpaperMode=Scaled
EOF

rm -rf "$TEMP_ASSETS"

# --- 5. DOCKERIZED BUILD & BINARY.SH OVERWRITE ---
echo "Starting Docker Build with surgical script patch..."
docker run --privileged --rm \
  -v "$(pwd)/../../build:/build" \
  -v "$(pwd)/../../output:/output" \
  -w /build \
  ubuntu:noble /bin/bash -c "
    export DEBIAN_FRONTEND=noninteractive
    
    # 1. Prepare Environment & Fix Paths
    apt-get update && apt-get install -y \
      live-build curl wget gnupg squashfs-tools xorriso \
      syslinux-utils syslinux-common isolinux \
      mtools dosfstools genisoimage

    # 2. OVERWRITE THE TROUBLEMAKER binary.sh
    # This replaces the script in the root of the build folder
    cat <<'INNEREOF' > /build/binary.sh
#!/bin/sh
echo 'RUNNING PATCHED BINARY.SH...'
genisoimage -J -l -cache-inodes -allow-multidot \
  -A \"HMLR_REVIVED\" \
  -p \"live-build 3.0\" \
  -publisher \"HMLR Project\" \
  -V \"HMLR_2026\" \
  -o binary.hybrid.iso binary
isohybrid binary.hybrid.iso
INNEREOF
    chmod +x /build/binary.sh

    # 3. Trinity Repo Setup
    mkdir -p config/archives
    echo 'deb http://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-r14.1.x noble main deps' > config/archives/trinity.list.chroot
    wget -qO- 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xC93AF1698685AD8B' | gpg --dearmor > config/archives/trinity.key.chroot
    cp config/archives/trinity.key.chroot config/archives/trinity.key.binary

    # 4. Config & Package Lists
    lb config \
      --mode ubuntu \
      --distribution noble \
      --binary-images iso-hybrid \
      --bootloader isolinux \
      --archive-areas 'main restricted universe multiverse'
    
    mkdir -p config/package-lists
    echo 'kubuntu-default-settings-trinity kubuntu-desktop-trinity ubiquity vlc' > config/package-lists/hmlr.list.chroot

    # 5. Execute Build
    lb build

    # 6. Export Results
    if [ -f binary.hybrid.iso ]; then
        mv binary.hybrid.iso /output/hmlr-revived-V4.iso
        echo 'SUCCESS: ISO EXPORTED TO OUTPUT FOLDER'
    else
        echo 'FATAL ERROR: Build failed to produce ISO'
        exit 1
    fi
"
