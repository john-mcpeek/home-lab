#!/usr/bin/env bash
set -euo pipefail

KUBESPRAY_VERSION=${KUBESPRAY_VERSION:-v2.28.1}

echo "WARNING: This will completely remove Kubernetes from all nodes!"
read -p "Are you sure you want to reset the cluster? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo "Reset cancelled"
    exit 0
fi

echo "Resetting Kubernetes cluster..."

docker run --rm -it \
    --mount type=bind,source="$(pwd)/../inventory/lab",dst=/inventory \
    --mount type=bind,source="${HOME}/.ssh",dst=/root/.ssh,readonly \
    "quay.io/kubespray/kubespray:${KUBESPRAY_VERSION}" \
    ansible-playbook -i /inventory/host.yaml \
    --become --become-user=root \
    --private-key=/root/.ssh/ansible \
    /kubespray/reset.yml \
    "$@"

echo "Cluster reset complete!"