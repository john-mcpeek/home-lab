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

PROXMOX_IP=$1
export PROXMOX_IP

MY_PUBLIC_KEY=$(cat ~/.ssh/id_ed25519.pub)
export MY_PUBLIC_KEY

if [ ! -f "$HOME/.ssh/ansible.pub" ]; then
  echo "Creating an ansible key."
  ssh-keygen -t ed25519 -f ansible -C ansible@home.lab
fi
#ANSIBLE_PUBLIC_KEY=$(cat ~/.ssh/ansible.pub)
#export ANSIBLE_PUBLIC_KEY

source "$(dirname "$0")/../k8s/utils/k8s_utils.sh"

K8S_VERSION=$(get_k8s_version)
export K8S_VERSION
echo "K8S_VERSION: ${K8S_VERSION}"

K8S_SERIES=$(get_k8s_series "${K8S_VERSION}")
export K8S_SERIES
echo "K8S_SERIES: ${K8S_SERIES}"

CAPI_API_VERSION=$(get_capi_version)
export CAPI_API_VERSION
echo "CAPI_API_VERSION: ${CAPI_API_VERSION}"

CAPI_NODE_VM_ID=$(get_capi_node_vm_id "${K8S_VERSION}")
export CAPI_NODE_VM_ID
echo "CAPI_NODE_VM_ID: ${CAPI_NODE_VM_ID}"

ssh "root@${PROXMOX_IP}" "rm -rf vms/cluster-api-manager/*"

scp -r cluster-api-manager/ "root@${PROXMOX_IP}":~/vms

ssh "root@${PROXMOX_IP}" "cd vms && ./cluster-api-manager/generate-cloud-init-files.sh '${PROXMOX_IP}' '${MY_PUBLIC_KEY}' '${CAPI_API_VERSION}' '${CAPI_NODE_VM_ID}' '${K8S_SERIES}' '${K8S_VERSION}'"
ssh "root@${PROXMOX_IP}" "cd vms && ./cluster-api-manager/build-vm.sh '${PROXMOX_IP}'"

# Configuration
HOST="cluster-api-manager.lab" # Replace with your server hostname/IP
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

if [ "$CONNECT_STATUS" = "true" ]; then
  echo "Waiting for cloud-init to complete..."
  ssh "$USER@$HOST" "sudo cloud-init status --wait" || true

  echo "Waiting for VM to be reachable after cloud-init reboot..."
  ssh-keygen -R "$HOST" 2>/dev/null || true
  post_ci_start=$(date +%s)
  until ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes \
        "$USER@$HOST" "true" 2>/dev/null; do
    if [ $(( $(date +%s) - post_ci_start )) -ge $TIMEOUT ]; then
      echo "Timed out waiting for $HOST after cloud-init reboot."
      exit 1
    fi
    sleep $INTERVAL
  done

  echo "Checking if CAPI base image VM (${CAPI_NODE_VM_ID}) already exists..."
  if ssh "root@${PROXMOX_IP}" "qm status ${CAPI_NODE_VM_ID}" &>/dev/null; then
    echo "VM ${CAPI_NODE_VM_ID} already exists, skipping image build."
  else
    echo "Execute the Kubernetes Cluster API Image Builder"
    ssh -t "$USER@$HOST" "cd /cluster-api/image-builder && ./build-capi-base-image.sh ${K8S_VERSION}"
  fi

  ssh "root@${PROXMOX_IP}" "qm set ${CAPI_NODE_VM_ID} --tags 'k8s capi_template'"

  echo "Copying CAPI cluster setup script."
  scp -r "$(dirname "$0")/../k8s" "$USER@$HOST":/cluster-api
else
  echo "$HOST was not accessible in the ${INTERVAL}s."
  exit 1
fi

echo "$0 complete"

echo "Cycling cluster-api-manager to free space"
ssh "root@${PROXMOX_IP}" "qm shutdown 10000"
ssh "root@${PROXMOX_IP}" "qm start 10000"
