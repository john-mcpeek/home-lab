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

  echo "BASE_TEMPLATE_VMID: $BASE_TEMPLATE_VMID, NEW_VM_VMID: $NEW_VM_VMID, GUESS_HOST_NAME: $GUESS_HOST_NAME, CORES: $CORES, RAM: $RAM, DNS_NODE_IP: $DNS_NODE_IP, tags: ${tags[@]}"

  qm clone $BASE_TEMPLATE_VMID $NEW_VM_VMID --pool $POOL --name $GUESS_HOST_NAME

  qm set $NEW_VM_VMID --cores $CORES
  qm set $NEW_VM_VMID --memory $RAM
  qm set $NEW_VM_VMID --cicustom "user=local:snippets/user-data-$GUESS_HOST_NAME.mime"
  qm set $NEW_VM_VMID --ipconfig0 "ip=10.0.0.$NEW_VM_VMID/24,gw=10.0.0.1"
  qm set $NEW_VM_VMID --nameserver "${DNS_NODE_IP} 75.75.75.75"
  qm set $NEW_VM_VMID "${tags[@]}"
}

export DNS_NODE_IP=$1
ANSIBLE_HOST_FILE=~/inventory/lab/host.yaml
export ANSIBLE_HOST_FILE

declare -A k8s_vms
while IFS="=" read -r key value; do k8s_vms[$key]=$value; done < <(
 cat $ANSIBLE_HOST_FILE | /snap/bin/yq '.all.hosts | to_entries | map([.key, .value.ip] | join("=")) | .[]' | tr -d '"'
)

for vm_name in "${!k8s_vms[@]}"; do
  export vm_name

  cores=$(cat $ANSIBLE_HOST_FILE  | /snap/bin/yq '.all.hosts | to_entries | .[] | select(.key == env(vm_name)) | .value.cores' )
  memory=$(cat $ANSIBLE_HOST_FILE | /snap/bin/yq '.all.hosts | to_entries | .[] | select(.key == env(vm_name)) | .value.memory')
  tags=$(cat $ANSIBLE_HOST_FILE   | /snap/bin/yq '.all.hosts | to_entries | .[] | select(.key == env(vm_name)) | .value.tags'  )

  vm_ip="${k8s_vms[$vm_name]}"
  last_octet="${vm_ip##*.}"
  vm_id="$last_octet"

  qm shutdown $vm_id
  qm destroy $vm_id

  clone_template 9999 $vm_id $vm_name $cores $memory dev $tags

  qm start $vm_id
done
