#!/bin/bash
# --- 1. Paths & Configuration ---
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
mkdir -p "$CHROOT/usr/lib"
mkdir -p "$CHROOT/usr/share/calamares/branding/hmlr"

# --- 3. IDENTITY & BRANDING ---
cat <<EOF > "$CHROOT/etc/os-release"
PRETTY_NAME="$HMLR_NAME"
NAME="$HMLR_NAME"
ID=hmlr
ID_LIKE=ubuntu
ANSI_COLOR="1;35"
EOF
cp "$CHROOT/etc/os-release" "$CHROOT/usr/lib/os-release"

# --- 4. TRINITY TRANSLATION (KDE4 to TDE) ---
echo "Translating KDE4 Theme Data for Trinity..."

# Map the Pink colors into the global Trinity config
cat <<EOF > "$CHROOT/etc/skel/.trinity/share/config/kdeglobals"
[General]
activeBackground=255,105,180
activeForeground=255,255,255
inactiveBackground=220,150,200
widgetStyle=plastik

[Icons]
Theme=hannah_montana

[WM]
active=255,105,180
inactive=220,150,200
EOF

# --- 5. CALAMARES (HOT PINK INSTALLER) ---
cat <<EOF > "$CHROOT/usr/share/calamares/branding/hmlr/branding.desc"
---
componentName:  hmlr
welcomeStyleCalamares:   true
welcomeExpandingLogo:   true
shortProductName:   HMLR
productName:        Hannah Montana Linux
sidebarBackground:  "#FF69B4"
sidebarText:        "#FFFFFF"
EOF

# --- 6. DOCKERIZED BUILD WITH GPG FIX ---
docker run --privileged --rm \
    -v "$(pwd)/../../build:/build" \
    -v "$(pwd)/../../output:/output" \
    -w /build \
    ubuntu:noble /bin/bash -c "
        set -x
        export DEBIAN_FRONTEND=noninteractive
        
        # 1. Essential Tooling
        apt-get update && apt-get install -y \
            live-build curl wget gnupg squashfs-tools xorriso \
            syslinux-utils syslinux-common isolinux \
            mtools dosfstools grub-common

        # 2. THE STABLE SYMLINKS (Secret Sauce)
        ln -sf /usr/bin/isohybrid /usr/local/bin/isohybrid
        ln -sf /usr/bin/isohybrid /bin/isohybrid

        # 3. THE GPG FIX (Corrected to Noble format)
        mkdir -p config/archives
        echo 'deb http://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-r14.1.x noble main deps' > config/archives/trinity.list.chroot
        
        # Pulling the key and forcing dearmor so it's not 'ignored' by Noble
        wget -qO- 'https://mirror.ppa.trinitydesktop.org/trinity/deb/trinity-keyring.gpg' | gpg --dearmor > config/archives/trinity.key.chroot
        cp config/archives/trinity.key.chroot config/archives/trinity.key.binary

        # 4. SURGICAL OVERWRITE (Inside Docker)
        mkdir -p scripts
        cat <<'INNEREOF' > scripts/binary.sh
#!/bin/bash
set -e
echo 'RUNNING HMLR PATCHED BINARY SCRIPT...'
lb binary_linux-image
lb binary_syslinux
lb binary_iso
INNEREOF
        chmod +x scripts/binary.sh

        # 5. CONFIG
        lb config \
            --mode ubuntu \
            --distribution noble \
            --architectures amd64 \
            --binary-images iso-hybrid \
            --bootloader isolinux \
            --archive-areas 'main restricted universe multiverse'

        # 6. PACKAGE LIST
        mkdir -p config/package-lists
        echo 'tde-trinity tde-style-plastik-trinity vlc screenfetch ubiquity' > config/package-lists/hmlr.list.chroot

        # 7. THE BUILD
        lb clean --purge
        # Use the surgical script to drive the binary stage
        lb build || ./scripts/binary.sh

        # 8. EXPORT (Rescue Logic)
        ISO_FILE=\$(find . -maxdepth 2 -name '*.iso' | head -n 1)
        if [ -n \"\$ISO_FILE\" ]; then
            mv \"\$ISO_FILE\" /output/hmlr-v4-revived.iso
            echo 'SUCCESS: ISO EXPORTED'
        else
            echo 'FATAL ERROR: Build failed to generate ISO'
            exit 1
        fi
    "
