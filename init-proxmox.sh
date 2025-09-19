#!/usr/bin/env bash
set -euo pipefail

# Check if no arguments are provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 PROXMOX_IP POSTGRES_PASSWORD"
    echo "Description: This script requires at least two argument to proceed."
    echo "Example: $0 10.0.0.10 password"
    exit 1
fi

export PROXMOX_IP=$1
export PROXMOX_PASSWORD=$2
MY_PUBLIC_KEY=$(cat ~/.ssh/id_ed25519.pub)
export MY_PUBLIC_KEY
ANSIBLE_PUBLIC_KEY=$(cat ~/.ssh/ansible.pub)
export ANSIBLE_PUBLIC_KEY

ssh-copy-id "root@${PROXMOX_IP}"

scp -r dns/ vms/ "root@${PROXMOX_IP}":~/

# Setup proxmox
ssh "root@${PROXMOX_IP}" "cd dns && ./proxmox-setup.sh ${PROXMOX_PASSWORD}"

# Setup Base VMs
ssh "root@${PROXMOX_IP}" "cd vms && ./base/generate-cloud-init-files.sh '$MY_PUBLIC_KEY' '$ANSIBLE_PUBLIC_KEY'"
ssh "root@${PROXMOX_IP}" "cd vms && ./base/build-base-templates.sh"