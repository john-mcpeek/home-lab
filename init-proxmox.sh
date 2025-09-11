#!/usr/bin/env bash

export PROXMOX_IP=$1
export PROXMOX_PASSWORD=$2
MY_PUBLIC_KEY=$(cat ~/.ssh/id_ed25519.pub)
export MY_PUBLIC_KEY

ssh-copy-id "root@${PROXMOX_IP}"

scp -r dns/ vms/ "root@${PROXMOX_IP}":~/

# Setup proxmox
ssh "root@${PROXMOX_IP}" "cd dns && ./proxmox-setup.sh ${PROXMOX_PASSWORD}"

# Setup Base VMs
ssh "root@${PROXMOX_IP}" "cd vms && ./base/generate-cloud-init-files.sh '$MY_PUBLIC_KEY'"
ssh "root@${PROXMOX_IP}" "cd vms && ./base/build-base-templates.sh"