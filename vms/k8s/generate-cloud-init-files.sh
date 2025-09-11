#!/usr/bin/env bash

function build_k8s_node_base() {
    export NODE_HOST_NAME=$1

    mkdir -p generated
    envsubst '${NODE_HOST_NAME}' < k8s/k8s-node-base.yaml | tee generated/k8s-node-base-${NODE_HOST_NAME}.yaml > /dev/null
}

function build_control_plane_cloud_init_file() {
    export NODE_HOST_NAME=$1
    export KEEP_ALIVE_D_STATE=$2
    export KEEP_ALIVE_D_PRIORITY=$3
    export KEEP_ALIVE_D_VIP=$4
    export CONTROL_PLANE_1_IP=$5
    export CONTROL_PLANE_2_IP=$6
    export CONTROL_PLANE_3_IP=$7

    build_k8s_node_base "${NODE_HOST_NAME}"
    envsubst '${KEEP_ALIVE_D_STATE} ${KEEP_ALIVE_D_PRIORITY} ${KEEP_ALIVE_D_VIP} ${CONTROL_PLANE_1_IP} ${CONTROL_PLANE_2_IP} ${CONTROL_PLANE_3_IP}' < k8s/api-server-ha-proxy.yaml | tee generated/api-server-ha-proxy-${NODE_HOST_NAME}.yaml > /dev/null


    cloud-init devel make-mime \
     -a generated/k8s-node-base-${NODE_HOST_NAME}.yaml:cloud-config \
     -a generated/api-server-ha-proxy-${NODE_HOST_NAME}.yaml:cloud-config \
     -a k8s/k8s-node-control-plane.yaml:cloud-config \
     > generated/user-data-${NODE_HOST_NAME}.mime
}

function build_worker_node_cloud_init_file() {
    export NODE_HOST_NAME=$1

    build_k8s_node_base "${NODE_HOST_NAME}"

    cloud-init devel make-mime \
     -a generated/k8s-node-base-${NODE_HOST_NAME}.yaml:cloud-config \
     > generated/user-data-${NODE_HOST_NAME}.mime
}

mkdir -p generated

build_control_plane_cloud_init_file cp-01 MASTER 101 10.0.0.200 10.0.0.201 10.0.0.202 10.0.0.203
build_control_plane_cloud_init_file cp-02 BACKUP 100 10.0.0.200 10.0.0.201 10.0.0.202 10.0.0.203
build_control_plane_cloud_init_file cp-03 BACKUP 100 10.0.0.200 10.0.0.201 10.0.0.202 10.0.0.203
build_worker_node_cloud_init_file   wk-01
build_worker_node_cloud_init_file   wk-02
build_worker_node_cloud_init_file   wk-03
build_worker_node_cloud_init_file   wk-04