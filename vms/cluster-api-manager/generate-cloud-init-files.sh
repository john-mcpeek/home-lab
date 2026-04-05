#!/usr/bin/env bash
set -euo pipefail

function build_vm_config() {
    export HOST_NAME=$1

    envsubst '${HOST_NAME} ${PROXMOX_IP} ${PROXMOX_SECRET} ${MY_PUBLIC_KEY} ${CAPI_API_VERSION} ${CAPI_NODE_VM_ID} ${K8S_SERIES} ${K8S_VERSION}' < "${HOST_NAME}/cloud-init.yaml" | tee "generated/${HOST_NAME}.yaml" > /dev/null

    cloud-init devel make-mime \
     -a "generated/${HOST_NAME}.yaml:cloud-config" \
     > "generated/user-data-${HOST_NAME}.mime"
}

export PROXMOX_IP=$1
export MY_PUBLIC_KEY=$2
export CAPI_API_VERSION=$3
export CAPI_NODE_VM_ID=$4
export K8S_SERIES=$5
export K8S_VERSION=$6
PROXMOX_SECRET=$(cat ~/image-builder.token | grep PROXMOX_SECRET | cut -d'=' -f2- | sed -e 's/\"//g')
export PROXMOX_SECRET

mkdir -p generated

build_vm_config cluster-api-manager

# Copy generated cloud-init files to snippets.
cp -f generated/*.mime /var/lib/vz/snippets/
echo "Generated cloud init config moved to snippets"