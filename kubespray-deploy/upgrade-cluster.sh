#!/usr/bin/env bash
set -euo pipefail

KUBESPRAY_VERSION=${KUBESPRAY_VERSION:-v2.28.1}

echo "Upgrading Kubernetes cluster..."

docker run --rm -it \
    --mount type=bind,source="$(pwd)/../inventory/lab",dst=/inventory \
    --mount type=bind,source="${HOME}/.ssh",dst=/root/.ssh,readonly \
    "quay.io/kubespray/kubespray:${KUBESPRAY_VERSION}" \
    ansible-playbook -i /inventory/host.yaml \
    --become --become-user=root \
    --private-key=/root/.ssh/ansible \
    /kubespray/upgrade-cluster.yml \
    "$@"

echo "Cluster upgrade complete!"