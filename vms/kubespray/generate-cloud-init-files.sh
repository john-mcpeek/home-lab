#!/usr/bin/env bash

function build_k8s_node_user_data() {
    export HOST_NAME=$1
    echo $HOST_NAME

    envsubst '${HOST_NAME}' < k8s/k8s-node-base.yaml | tee generated/k8s-node-base-${HOST_NAME}.yaml > /dev/null

    cloud-init devel make-mime \
     -a generated/k8s-node-base-${HOST_NAME}.yaml:cloud-config \
     > generated/user-data-${HOST_NAME}.mime
}

mkdir -p generated

declare -A k8s_vms
while IFS="=" read -r key value; do k8s_vms["$key"]=$value; done < <(
 /snap/bin/yq '.all.hosts | to_entries | map([.key, .value.ip] | join("=")) | .[]' ~/inventory/lab/host.yaml
)

for vm_name in "${!k8s_vms[@]}"; do
  build_k8s_node_user_data $vm_name
done

# Copy generated cloud-init files to snippets.
cp -f generated/*.mime /var/lib/vz/snippets/
echo "Generated cloud init config moved to snippets"