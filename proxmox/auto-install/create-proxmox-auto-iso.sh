#!/bin/bash
# ================================================================
# Proxmox VE Automated USB Creator
# - Finds latest Proxmox ISO
# - Creates custom ISO with answer.toml
# - Detects USB thumb drive, wipes it, and writes the ISO
# ================================================================

set -euo pipefail

# ================== Configuration ==================
ANSWER_FILE="$(pwd)/answer.toml"
CUSTOM_ISO="proxmox-ve-auto-install.iso"
WORK_DIR="/tmp/proxmox-auto-iso"
DOWNLOAD_DIR="$HOME/Downloads"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Proxmox VE Automated USB Creator (Latest Version) ===${NC}"

# Create directories
mkdir -p "$DOWNLOAD_DIR" "$WORK_DIR"

# ================== Install Dependencies ==================
echo -e "${YELLOW}Installing required packages...${NC}"
apt-get update -qq
apt-get install -y proxmox-auto-install-assistant curl wget xorriso

# ================== Find Latest ISO ==================
echo -e "${YELLOW}Finding the latest Proxmox VE ISO...${NC}"

# More robust way to get the latest proxmox-ve_*.iso
LATEST_ISO=$(curl -s http://download.proxmox.com/iso/ | \
    grep -oE 'proxmox-ve_[0-9]+\.[0-9]+-[0-9]+\.iso' | \
    sort -V | tail -n 1)

if [[ -z "$LATEST_ISO" ]]; then
    echo -e "${RED}Error: Could not detect latest ISO from mirror.${NC}"
    echo "Falling back to known latest: proxmox-ve_9.1-1.iso"
    LATEST_ISO="proxmox-ve_9.1-1.iso"
fi

echo -e "${GREEN}Latest ISO detected: ${YELLOW}$LATEST_ISO${NC}"

ISO_URL="http://download.proxmox.com/iso/$LATEST_ISO"
ISO_PATH="$DOWNLOAD_DIR/$LATEST_ISO"

# ================== Download ISO if needed ==================
cd "$DOWNLOAD_DIR"

if [[ ! -f "$LATEST_ISO" ]]; then
    echo -e "${YELLOW}Downloading $LATEST_ISO (this may take a while)...${NC}"
    wget --progress=bar:force:noscroll -O "$LATEST_ISO" "$ISO_URL"
else
    echo -e "${GREEN}Using existing local copy: $LATEST_ISO${NC}"
fi

# ================== Validate Answer File ==================
echo -e "${YELLOW}Validating $ANSWER_FILE ...${NC}"
if [[ ! -f "$ANSWER_FILE" ]]; then
    echo -e "${RED}Error: $ANSWER_FILE not found in current directory!${NC}"
    exit 1
fi

proxmox-auto-install-assistant validate-answer "$ANSWER_FILE"
echo -e "${GREEN}Answer file is valid.${NC}"

# ================== Create Custom ISO ==================
echo -e "${YELLOW}Building custom automated ISO...${NC}"

proxmox-auto-install-assistant prepare-iso \
    "$ISO_PATH" \
    --fetch-from iso \
    --answer-file "$ANSWER_FILE" \
    --output "$WORK_DIR/$CUSTOM_ISO"

mv "$WORK_DIR/$CUSTOM_ISO" "./$CUSTOM_ISO"

echo -e "${GREEN}Custom ISO created: ${YELLOW}./$CUSTOM_ISO${NC}"

# ================== Detect USB Thumb Drive ==================
echo -e "${YELLOW}Detecting USB thumb drive...${NC}"

# Find removable disks (hotplug=1), exclude loop and small drives (<4GB)
USB_DEVICES=$(lsblk -o NAME,HOTPLUG,SIZE,TYPE -n -l | \
    awk '$2 == "1" && $4 == "disk" && $3 ~ /[0-9.]+[GT]/ {print "/dev/" $1}')

if [[ -z "$USB_DEVICES" ]]; then
    echo -e "${RED}No removable USB drive detected.${NC}"
    echo "Please insert a USB drive (>= 4GB) and run again."
    exit 1
fi

if [[ $(echo "$USB_DEVICES" | wc -l) -gt 1 ]]; then
    echo -e "${YELLOW}Multiple USB drives found:${NC}"
    echo "$USB_DEVICES"
    read -rp "Enter the device to use (e.g. /dev/sdb): " USB_DEVICE
else
    USB_DEVICE=$(echo "$USB_DEVICES" | head -n 1)
fi

read -rp "WARNING: All data on $USB_DEVICE will be permanently erased! Type 'yes' to continue: " CONFIRM
if [[ "$CONFIRM" != "yes" && "$CONFIRM" != "y" ]]; then
    echo "Aborted by user."
    exit 1
fi

# ================== Wipe and Write ISO to USB ==================
echo -e "${YELLOW}Wiping and writing ISO to $USB_DEVICE ...${NC}"
echo -e "${RED}This may take several minutes. Do not unplug the drive!${NC}"

# Unmount any partitions first
umount "${USB_DEVICE}"* 2>/dev/null || true

# Write the ISO
sudo dd if="./$CUSTOM_ISO" of="$USB_DEVICE" bs=4M status=progress oflag=dsync conv=fsync

echo -e "${GREEN}ISO successfully written to USB!${NC}"

# Sync and eject
sync
sudo eject "$USB_DEVICE" 2>/dev/null || true

echo ""
echo -e "${GREEN}=== Done! ===${NC}"
echo "You can now safely remove the USB drive."
echo "Boot from it on your target machine for fully automated Proxmox installation."

ls -lh "./$CUSTOM_ISO"