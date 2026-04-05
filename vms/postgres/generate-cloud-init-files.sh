#!/usr/bin/env bash
set -euo pipefail

function build_postgres_vm_config() {
    export HOST_NAME=$1

    envsubst '${HOST_NAME} ${POSTGRES_PASSWORD}' < "${HOST_NAME}/cloud-init.yaml" | tee "generated/${HOST_NAME}.yaml" > /dev/null

    cloud-init devel make-mime \
     -a "generated/${HOST_NAME}.yaml:cloud-config" \
     > "generated/user-data-${HOST_NAME}.mime"
}

export MY_PUBLIC_KEY=$1
export POSTGRES_PASSWORD=$2

mkdir -p generated

build_postgres_vm_config postgres

# Copy generated cloud-init files to snippets.
cp -f generated/*.mime /var/lib/vz/snippets/
echo "Generated cloud init config moved to snippets"