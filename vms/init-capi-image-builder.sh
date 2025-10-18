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

ssh "root@${PROXMOX_IP}" "rm -rf vms/cluster-api-image-builder-builder/*"

scp -r cluster-api-image-builder-builder/ "root@${PROXMOX_IP}":~/vms

ssh "root@${PROXMOX_IP}" "cd vms && ./cluster-api-image-builder-builder/generate-cloud-init-files.sh ${PROXMOX_IP}"
ssh "root@${PROXMOX_IP}" "cd vms && ./cluster-api-image-builder-builder/build-vm.sh ${PROXMOX_IP}"

## Configuration
HOST="10.0.0.222" # Replace with your server hostname/IP
USER="john"       # Replace with your SSH username
INTERVAL=10       # Retry interval in seconds
TIMEOUT=300       # Total timeout in seconds (5 minutes)

start_time=$(date +%s)
echo "Testing SSH access to $USER@$HOST for up to 5 minutes..."

ssh-keygen -R "$HOST"

CONNECT_STATUS=false
while [ $(( $(date +%s) - start_time )) -lt $TIMEOUT ]; do
    if ssh -o ConnectTimeout=10 \
           -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=~/.ssh/known_hosts \
           -o BatchMode=yes \
           "$USER@$HOST" "echo 'SSH access successful'" 2>/dev/null; then
        echo "SSH access to $USER@$HOST is now available!"

        CONNECT_STATUS=true
        break
    else
        echo "$(date): SSH access failed, retrying in ${INTERVAL}s..."
        sleep $INTERVAL
    fi
done

echo "Initial 30 second wait..."
sleep 30

if [ $CONNECT_STATUS ]; then
  echo "Execute the Kubernetes Cluster API Image Builder"
  ssh -t "$USER@$HOST" "cd /cluster-api && ./build-cluster-api-vm.sh"
else
  echo "$HOST was not accessible in the ${INTERVAL}s."
  exit 1
fi

echo "$0 complete"