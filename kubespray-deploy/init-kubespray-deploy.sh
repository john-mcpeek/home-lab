#!/usr/bin/env bash
set -euo pipefail

KUBESPRAY_VERSION=${1:-v2.28.1}

echo "Setting up Kubespray deployment with version ${KUBESPRAY_VERSION}..."

# Pull the official Kubespray container
echo "Pulling Kubespray container image..."
docker pull "quay.io/kubespray/kubespray:${KUBESPRAY_VERSION}"

# Create SSH config for ansible user if needed
if [ ! -f "$HOME/.ssh/ansible" ]; then
    echo "Warning: ansible SSH key not found at ~/.ssh/ansible"
    echo "Make sure the ansible SSH key exists before deploying"
fi

echo "Kubespray deployment setup complete!"
echo "Run ./deploy-k8s.sh to deploy Kubernetes cluster"