#!/usr/bin/env bash

function build_vm_config() {
    export HOST_NAME=$1

    envsubst '${HOST_NAME} ${MY_PUBLIC_KEY} ${PROXMOX_ROOT_PUBLIC_KEY}' < cluster-api/image-builder.yaml | tee generated/${HOST_NAME}.yaml > /dev/null

    cloud-init devel make-mime \
     -a generated/${HOST_NAME}.yaml:cloud-config \
     > generated/user-data-${HOST_NAME}.mime
}

export MY_PUBLIC_KEY=$1

PROXMOX_ROOT_PUBLIC_KEY=$(cat /root/.ssh/id_rsa.pub)
export PROXMOX_ROOT_PUBLIC_KEY

mkdir -p generated

build_vm_config image-builder

# Copy generated cloud-init files to snippets.
cp -f generated/*.mime /var/lib/vz/snippets/
echo "Generated cloud init config moved to snippets"