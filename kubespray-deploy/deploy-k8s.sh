#!/usr/bin/env bash
set -euo pipefail

KUBESPRAY_VERSION=${KUBESPRAY_VERSION:-v2.28.1}
ACTION=${1:-cluster.yml}

# Check if ansible SSH key exists
if [ ! -f "$HOME/.ssh/ansible" ]; then
    echo "Error: ansible SSH key not found at ~/.ssh/ansible"
    exit 1
fi

echo "Deploying Kubernetes cluster using Kubespray ${KUBESPRAY_VERSION}..."
echo "Running playbook: ${ACTION}"

# Run Kubespray container with necessary mounts
docker run --rm -it \
    --mount type=bind,source="$(pwd)/../inventory/lab",dst=/inventory \
    --mount type=bind,source="${HOME}/.ssh",dst=/root/.ssh,readonly \
    "quay.io/kubespray/kubespray:${KUBESPRAY_VERSION}" \
    ansible-playbook -i /inventory/host.yaml \
    --become --become-user=root \
    --private-key=~/.ssh/ansible \
    "/kubespray/${ACTION}" \
    "${@:2}"

echo "Kubernetes deployment complete!"