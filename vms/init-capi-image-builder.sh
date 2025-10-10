#!/usr/bin/env bash
set -euo pipefail

# Check if no arguments are provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 PROXMOX_IP"
    echo "Description: This script requires at least one argument to proceed."
    echo "Example: $0 10.0.0.10"
    exit 1
fi

echo "##########################################################"
echo "Starting: $0"

export PROXMOX_IP=$1

ssh "root@${PROXMOX_IP}" "rm -rf vms/cluster-api/*"

scp -r cluster-api/ "root@${PROXMOX_IP}":~/vms

ssh "root@${PROXMOX_IP}" "cd vms && ./cluster-api/generate-cloud-init-files.sh"
ssh "root@${PROXMOX_IP}" "cd vms && ./cluster-api/build-image-builder-vm.sh ${PROXMOX_IP}"

echo "$0 complete"