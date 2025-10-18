#!/usr/bin/env bash
set -euo pipefail

# Check if no arguments are provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 PROXMOX_IP PROXMOX_PASSWORD POSTGRES_PASSWORD"
    echo "Description: This script requires three argument to proceed."
    echo "Example: $0 10.0.0.10 password postgres_password"
    exit 1
fi

export PROXMOX_IP=$1
export PROXMOX_PASSWORD=$2
export POSTGRES_PASSWORD=$3


ssh-copy-id -i ~/.ssh/id_ed25519 "root@${PROXMOX_IP}"

# Clean up, just in case.
ssh "root@${PROXMOX_IP}" "rm -rf proxmox k8s vms"
find . -type f -not -path '*/.*/*' -exec dos2unix {} \;

scp -r proxmox/  k8s/ vms/ "root@${PROXMOX_IP}":~/

# Setup proxmox
ssh "root@${PROXMOX_IP}" "cd proxmox && ./proxmox-setup.sh ${PROXMOX_PASSWORD}"

# Setup VMs
cd vms
./init-base.sh "${PROXMOX_IP}"
./init-blank.sh "${PROXMOX_IP}"
./init-postgres.sh "${PROXMOX_IP}" "${POSTGRES_PASSWORD}"
./init-capi-image-builder.sh "${PROXMOX_IP}"
#./init-capi-base-vm.sh "${PROXMOX_IP}"