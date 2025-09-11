#!/usr/bin/env bash

function build_postgres_vm_config() {
    local NODE_HOST_NAME=$1

#    mkdir -p generated
    envsubst '${NODE_HOST_NAME}' < postgres/database.yaml | tee generated/database-${NODE_HOST_NAME}.yaml > /dev/null

    cloud-init devel make-mime \
     -a generated/database-${NODE_HOST_NAME}.yaml:cloud-config \
     > generated/user-data-${NODE_HOST_NAME}.mime
}

mkdir -p generated

build_postgres_vm_config postgres