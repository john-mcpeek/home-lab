#!/usr/bin/env bash
set -euo pipefail

# Check if no arguments are provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 PROXMOX_IP PROXMOX_PASSWORD POSTGRES_PASSWORD"
    echo "Description: This script requires at least two argument to proceed."
    echo "Example: $0 10.0.0.10 proxmox_password postgres_password"
    exit 1
fi

export PROXMOX_IP=$1
export PROXMOX_PASSWORD=$2
export POSTGRES_PASSWORD=$3


ssh-copy-id -i ~/.ssh/id_ed25519 "root@${PROXMOX_IP}"

# Clean up, just in case.
ssh "root@${PROXMOX_IP}" "rm -rf dns vms"
find . -type f -exec dos2unix {} \;

scp -r dns/ vms/ "root@${PROXMOX_IP}":~/

# Setup proxmox
ssh "root@${PROXMOX_IP}" "cd dns && ./proxmox-setup.sh ${PROXMOX_PASSWORD}"

# Setup VMs
cd vms
./init-base.sh $PROXMOX_IP
./init-blank.sh $PROXMOX_IP
./init-kubespray.sh $PROXMOX_IP
./init-postgres.sh $PROXMOX_IP $POSTGRES_PASSWORD