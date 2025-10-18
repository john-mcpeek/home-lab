#!/usr/bin/env bash


function update_keys() {
  envsubst '${HOST_NAME} ${MY_PUBLIC_KEY} ${ANSIBLE_PUBLIC_KEY} ${PROXMOX_ROOT_PUBLIC_KEY}' < cluster-api-image-builder/capi.yaml | tee generated/capi.yaml > /dev/null
}

function dns_self_register() {
  cloud-init devel make-mime \
    -a generated/capi.yaml:cloud-config \
    -a generated/base-dns-self-register.yaml:cloud-config \
    > generated/user-data-capi.mime
}

export HOST_NAME=$1
export MY_PUBLIC_KEY=$2
export ANSIBLE_PUBLIC_KEY=$3

PROXMOX_ROOT_PUBLIC_KEY=$(cat /root/.ssh/id_rsa.pub)
export PROXMOX_ROOT_PUBLIC_KEY

mkdir -p generated

update_keys
dns_self_register

# Copy generated cloud-init files to snippets.
cp -f generated/*.mime /var/lib/vz/snippets/
echo "Generated cloud init config moved to snippets"