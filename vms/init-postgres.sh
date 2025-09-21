#!/usr/bin/env bash
set -euo pipefail

# Check if no arguments are provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 PROXMOX_IP POSTGRES_PASSWORD"
    echo "Description: This script requires at least two argument to proceed."
    echo "Example: $0 10.0.0.10 password"
    exit 1
fi

echo "##########################################################"
echo "Starting: $0"

export PROXMOX_IP=$1
export POSTGRES_PASSWORD=$2

MY_PUBLIC_KEY=$(cat ~/.ssh/id_ed25519.pub)
export MY_PUBLIC_KEY

ssh "root@${PROXMOX_IP}" "rm -rf vms/postgres/*"

scp -r postgres/ "root@${PROXMOX_IP}":~/vms

ssh "root@${PROXMOX_IP}" "cd vms && ./postgres/generate-cloud-init-files.sh '${MY_PUBLIC_KEY}' ${POSTGRES_PASSWORD}"
ssh "root@${PROXMOX_IP}" "cd vms && ./postgres/build-postgres-vm.sh ${PROXMOX_IP}"

echo "$0 complete"