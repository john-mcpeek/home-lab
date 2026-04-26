#!/usr/bin/env bash
set -euo pipefail

# Check if no arguments are provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 PROXMOX_IP"
    echo "Description: This script requires one argument to proceed. The Proxmox root password is read from ./root-password and the Postgres password from ./postgres-password."
    echo "Example: $0 10.0.0.10"
    exit 1
fi

if [ ! -f ./root-password ]; then
    echo "Error: ./root-password file not found. Create it with the Proxmox root password."
    exit 1
fi

if [ ! -f ./postgres-password ]; then
    echo "Error: ./postgres-password file not found. Create it with the Postgres password."
    exit 1
fi

export PROXMOX_IP=$1
export PROXMOX_PASSWORD=$(cat ./root-password)
export POSTGRES_PASSWORD=$(cat ./postgres-password)

if ! command -v sshpass &>/dev/null; then
    sudo apt-get install -y sshpass
fi
ssh-keygen -R "${PROXMOX_IP}" || true
ssh-keygen -F "${PROXMOX_IP}" &>/dev/null || ssh-keyscan -H "${PROXMOX_IP}" >> ~/.ssh/known_hosts
sshpass -p "${PROXMOX_PASSWORD}" ssh-copy-id -i ~/.ssh/id_ed25519 "root@${PROXMOX_IP}"

# Clean up, just in case.
ssh "root@${PROXMOX_IP}" "rm -rf proxmox k8s vms"
find . -type f -not -path '*/.*/*' -exec dos2unix {} \;

scp -r proxmox/  k8s/ vms/ "root@${PROXMOX_IP}":~/

# Setup proxmox
ssh "root@${PROXMOX_IP}" "cd proxmox && ./proxmox-setup.sh ${PROXMOX_PASSWORD}"

# Generate SHA-512 hash of the root password on Proxmox and update answer.toml in place
ssh "root@${PROXMOX_IP}" "
    if ! command -v mkpasswd &>/dev/null; then
        apt install -y whois
    fi
    HASH=\$(mkpasswd -m sha-512 '${PROXMOX_PASSWORD}')
    sed -i \"s|^root-password-hashed = .*|root-password-hashed = \\\"\${HASH}\\\"|\" ~/proxmox/auto-install/answer.toml
"

# Setup VMs
cd vms
./init-base.sh "${PROXMOX_IP}"
./init-blank.sh "${PROXMOX_IP}"
./init-postgres.sh "${PROXMOX_IP}" "${POSTGRES_PASSWORD}"
./init-capi-manager.sh "${PROXMOX_IP}"