#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 PROXMOX_IP [--force-rebuild]"
    echo "Description: Build the base Ubuntu template (VM 9999) on Proxmox."
    echo "  --force-rebuild  Destroy and recreate the template even if it already exists."
    echo "Example: $0 10.0.0.10"
    echo "Example: $0 10.0.0.10 --force-rebuild"
    exit 1
}

if [ $# -eq 0 ]; then
    usage
fi

PROXMOX_IP=""
FORCE_REBUILD_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --force-rebuild)
      FORCE_REBUILD_ARGS=(--force-rebuild)
      ;;
    -h|--help)
      usage
      ;;
    *)
      if [ -z "$PROXMOX_IP" ]; then
        PROXMOX_IP=$arg
      else
        echo "Unknown argument: $arg"
        usage
      fi
      ;;
  esac
done

if [ -z "$PROXMOX_IP" ]; then
  usage
fi

echo "##########################################################"
echo "Starting: $0"

export PROXMOX_IP

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
if [ ${#FORCE_REBUILD_ARGS[@]} -gt 0 ]; then
  ssh "root@${PROXMOX_IP}" "cd vms && ./base/build-vm.sh --force-rebuild"
else
  ssh "root@${PROXMOX_IP}" "cd vms && ./base/build-vm.sh"
fi

echo "$0 complete"
