#!/usr/bin/env bash

function build_vm_config() {
    export HOST_NAME=$1

    envsubst '${HOST_NAME} ${PROXMOX_IP} ${PROXMOX_TOKEN}' < cluster-api-image-builder-builder/image-builder.yaml | tee generated/${HOST_NAME}.yaml > /dev/null

    cloud-init devel make-mime \
     -a generated/${HOST_NAME}.yaml:cloud-config \
     > generated/user-data-${HOST_NAME}.mime
}

export DNS_SERVER_IP=$1
PROXMOX_TOKEN=$(cat ~/image-builder.token | grep PROXMOX_TOKEN | cut -d'=' -f2-)
export PROXMOX_TOKEN

mkdir -p generated

build_vm_config image-builder

# Copy generated cloud-init files to snippets.
cp -f generated/*.mime /var/lib/vz/snippets/
echo "Generated cloud init config moved to snippets"