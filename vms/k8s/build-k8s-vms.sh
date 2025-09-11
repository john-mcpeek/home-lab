#!/usr/bin/env bash

function clone_template() {
  local BASE_TEMPLATE_VMID=$1
  local NEW_VM_VMID=$2
  local GUESS_HOST_NAME=$3
  local CORES=$4
  local RAM=$5
  local POOL=$6
  shift; shift; shift; shift; shift; shift;
  local -a tag_names=("$@")
  local -a tags=()
  for name in "${tag_names[@]}"; do
    tags[${#tags[@]}]="--tags"
    tags[${#tags[@]}]="$name"
  done

  qm clone $BASE_TEMPLATE_VMID $NEW_VM_VMID --pool $POOL --name $GUESS_HOST_NAME

  qm set $NEW_VM_VMID --cores $CORES
  qm set $NEW_VM_VMID --memory $RAM
  qm set $NEW_VM_VMID --cicustom "user=local:snippets/user-data-$GUESS_HOST_NAME.mime"
  qm set $NEW_VM_VMID --sshkey ~/.ssh/id_rsa.pub
  qm set $NEW_VM_VMID --ipconfig0 "ip=10.0.0.$NEW_VM_VMID/24,gw=10.0.0.1"
  qm set $NEW_VM_VMID --nameserver "10.0.0.10 75.75.75.75"
  qm set $NEW_VM_VMID "${tags[@]}"
}

qm shutdown 201 && qm shutdown 202 && qm shutdown 203 && qm shutdown 204 && qm shutdown 205 && qm shutdown 206 && qm shutdown 207
qm destroy 201 && qm destroy 202 && qm destroy 203 && qm destroy 204 && qm destroy 205 && qm destroy 206 && qm destroy 207

clone_template 9999 201 cp-01 3 4096 dev "k8s control-plane"
clone_template 9999 202 cp-02 3 4096 dev "k8s control-plane"
clone_template 9999 203 cp-03 3 4096 dev "k8s control-plane"
clone_template 9999 204 wk-01 4 8192 dev "k8s worker"
clone_template 9999 205 wk-02 4 8192 dev "k8s worker"
clone_template 9999 206 wk-03 4 8192 dev "k8s worker"
clone_template 9999 207 wk-04 4 8192 dev "k8s worker"

