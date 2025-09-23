#!/usr/bin/env bash
set -euo pipefail

KUBESPRAY_VERSION=${KUBESPRAY_VERSION:-v2.28.1}

echo "Scaling Kubernetes cluster (add/remove nodes)..."
echo "Make sure you've updated inventory/lab/host.yaml with new nodes"

docker run --rm -it \
    --mount type=bind,source="$(pwd)/../inventory/lab",dst=/inventory \
    --mount type=bind,source="${HOME}/.ssh",dst=/root/.ssh,readonly \
    "quay.io/kubespray/kubespray:${KUBESPRAY_VERSION}" \
    ansible-playbook -i /inventory/host.yaml \
    --become --become-user=root \
    --private-key=/root/.ssh/ansible \
    /kubespray/scale.yml \
    "$@"

echo "Cluster scaling complete!"