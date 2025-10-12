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


if [ ! -f "$HOME/.ssh/id_ed25519.pub" ]; then
  echo "***********************************************************"
  echo "You need an ssh key. In this case an Ed25519 algorithm key."
  echo "***********************************************************"
  exit 1;
fi
MY_PUBLIC_KEY=$(cat ~/.ssh/id_ed25519.pub)
export MY_PUBLIC_KEY

if [ ! -f "$HOME/.ssh/ansible.pub" ]; then
  echo "Creating an ansible key."
  ssh-keygen -t ed25519 -f ansible -C ansible@home.lab
fi
ANSIBLE_PUBLIC_KEY=$(cat ~/.ssh/ansible.pub)
export ANSIBLE_PUBLIC_KEY

ssh "root@${PROXMOX_IP}" "rm -rf vms/base/*"

scp -r base/ "root@${PROXMOX_IP}":~/vms

ssh "root@${PROXMOX_IP}" "cd vms && ./base/generate-cloud-init-files.sh '${MY_PUBLIC_KEY}' '${ANSIBLE_PUBLIC_KEY}'"
ssh "root@${PROXMOX_IP}" "cd vms && ./base/build-base-templates.sh"

echo "$0 complete"