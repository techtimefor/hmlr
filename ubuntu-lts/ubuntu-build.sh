#!/bin/bash
# --- 1. Paths & Configuration ---
# Ensures everything stays within the current 'hmlr' directory
BASE_DIR=$(pwd)
BUILD_DIR="$BASE_DIR/build"
OUTPUT_DIR="$BASE_DIR/output"
DATA_DIR="$BASE_DIR/original_hml_data"
CHROOT="$BUILD_DIR/config/includes.chroot"

HMLR_NAME="Hannah Montana Linux Revived V4"
UBUNTU_CODENAME="noble"

echo "--- Initializing HMLR V4 Build Environment ---"

# --- 2. Clean & Setup ---
sudo rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
mkdir -p "$CHROOT/etc/skel/.trinity/share/config"
mkdir -p "$CHROOT/usr/lib" # Fixes the os-release cp error
mkdir -p "$CHROOT/etc/calamares/modules"
mkdir -p "$CHROOT/usr/share/calamares/branding/hmlr"

# --- 3. IDENTITY & BRANDING ---
echo "Configuring OS Identity..."
cat <<EOF > "$CHROOT/etc/os-release"
PRETTY_NAME="$HMLR_NAME"
NAME="$HMLR_NAME"
ID=hmlr
ID_LIKE=ubuntu
ANSI_COLOR="1;35"
EOF

# Defensively copy to /usr/lib/ to satisfy the build system
cp "$CHROOT/etc/os-release" "$CHROOT/usr/lib/os-release"

# --- 4. THE PINK TRINITY PATCH (Window Decorations) ---
echo "Applying Pink Window Decoration Patch..."
cat <<EOF > "$CHROOT/etc/skel/.trinity/share/config/kdeglobals"
[General]
activeBackground=255,105,180
activeForeground=255,255,255
inactiveBackground=220,150,200
Wallpaper=/usr/share/wallpapers/hml_default.png

[Icons]
Theme=hannah_montana

[WM]
active=255,105,180
inactive=220,150,200
frame=255,192,203
EOF

# --- 5. CALAMARES (INSTALLER) CONFIG ---
echo "Configuring Calamares (Replacing Ubiquity)..."
cat <<EOF > "$CHROOT/usr/share/calamares/branding/hmlr/branding.desc"
---
componentName:  hmlr
welcomeStyleCalamares:   true
welcomeExpandingLogo:   true
windowExpansion:    normal
shortProductName:   HMLR
productName:        Hannah Montana Linux Revived
sidebarBackground:  "#FF69B4"
sidebarText:        "#FFFFFF"
sidebarTextHighlight: "#FFC0CB"
EOF

# --- 6. DOCKERIZED COMPILATION & SURGICAL PATCHING ---
echo "Starting Docker Build..."
docker run --privileged --rm \
  -v "$BUILD_DIR:/build" \
  -v "$OUTPUT_DIR:/output" \
  -v "$DATA_DIR:/data" \
  -w /build \
  ubuntu:noble /bin/bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
      live-build curl wget gnupg squashfs-tools xorriso \
      syslinux-utils syslinux-common isolinux calamares \
      mtools dosfstools genisoimage

    # SURGICAL PATCH: Overwrite binary.sh to ensure hybrid ISO creation
    mkdir -p scripts
    cat <<'INNEREOF' > scripts/binary.sh
#!/bin/sh
echo 'RUNNING HMLR PATCHED BINARY SCRIPT...'
lb binary_linux-image
lb binary_syslinux
lb binary_iso
INNEREOF
    chmod +x scripts/binary.sh

    # Setup Trinity Repos for Noble
    mkdir -p config/archives
    echo 'deb http://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-r14.1.x noble main deps' > config/archives/trinity.list.chroot
    curl -fsSL https://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-keyring.deb -o keyring.deb
    cp keyring.deb config/packages.chroot/

    # Configure Live-Build
    lb config \
      --mode ubuntu \
      --distribution noble \
      --binary-images iso-hybrid \
      --architectures amd64 \
      --linux-flavours generic \
      --archive-areas 'main restricted universe multiverse'

    # Package List: Trinity + Calamares
    echo 'tde-trinity calamares calamares-settings-ubuntu vlc' > config/package-lists/hmlr.list.chroot

    # Run the Build
    lb build

    # Move result to output
    [ -f *.iso ] && mv *.iso /output/hmlr-v4-trinity.iso
"
