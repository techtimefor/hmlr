#!/bin/bash

# --- OS Detection ---
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
else
    echo "Could not detect OS."
    exit 1
fi

# --- Dependency Check (Whiptail) ---
if ! command -v whiptail &> /dev/null; then
    echo "Whiptail not found. Installing..."
    case "$DISTRO" in
        debian|ubuntu) sudo apt update && sudo apt install -y whiptail ;;
        arch)          sudo pacman -S --noconfirm libnewt ;; 
        fedora|rhel)   sudo dnf install -y newt ;;
        *) echo "Please install whiptail manually."; exit 1 ;;
    esac
fi

# --- Functions ---

ensure_docker() {
    if ! command -v docker &> /dev/null; then
        whiptail --title "Docker Required" --yesno "Docker is not installed. Install it now?" 10 60
        if [ $? -eq 0 ]; then
            case "$DISTRO" in
                debian|ubuntu) sudo apt update && sudo apt install -y docker.io ;;
                arch)          sudo pacman -S --noconfirm docker ;;
                fedora|rhel)   sudo dnf install -y docker ;;
            esac
            sudo systemctl enable --now docker
        else
            return 1
        fi
    fi

    if ! groups $USER | grep -q '\bdocker\b'; then
        whiptail --title "Permissions" --msgbox "Adding $USER to docker group. You MUST relog after this script!" 10 60
        sudo usermod -aG docker $USER
    fi
}

# --- Main Menu Loop ---
while true; do
    CHOICE=$(whiptail --title "HMLR Master Control" \
    --menu "Select a task to prepare your workspace" 18 65 6 \
    "1" "Setup Docker (Install & Permissions)" \
    "2" "Build Debian 12 (Assets & ISO)" \
    "3" "Build Debian 13 (Assets & ISO)" \
    "4" "Build Ubuntu LTS (Trinity Specialized)" \
    "5" "About & Support" \
    "6" "Exit" 3>&1 1>&2 2>&3)

    case $CHOICE in
        1)
            ensure_docker && whiptail --msgbox "Docker environment is ready!" 10 40
            ;;
        4)
            if [ -f "./ubuntu-lts/ubuntu-build.sh" ]; then
                chmod +x ./ubuntu-lts/ubuntu-build.sh
                ./ubuntu-lts/ubuntu-build.sh
            else
                whiptail --title "Error" --msgbox "Sub-script ./ubuntu-lts/ubuntu-build.sh not found!" 10 60
            fi
            ;;
        2|3)
            whiptail --msgbox "Debian build logic coming soon. Use Option 4 for the primary Ubuntu build." 10 60
            ;;
        5)
            whiptail --title "About" --msgbox "Hannah Montana Linux Revived (2026)\n\nStage 1: Setup Docker\nStage 2: Inject Legacy Assets into Trinity\n\nRepo: https://github.com/techtimefor/hmlr" 12 60
            ;;
        *)
            echo "Exiting..."
            break
            ;;
    esac
done
