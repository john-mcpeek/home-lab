#!/usr/bin/env bash

export DNS_SERVER_IP=$1

qm shutdown 8888
qm destroy  8888

scp john@10.0.0.222:/cluster-api/proxmox_packer_overrides.json generated/proxmox_packer_overrides.json

K8S_VERSION=$(cat generated/proxmox_packer_overrides.json | jq -r '.kubernetes_semver')
capi_image_name=$(echo "ubuntu-2404-kube-${K8S_VERSION}")
capi_vmid=$(qm list | grep "$capi_image_name" | awk '{print $1}')
echo "capi image name: $capi_image_name"
echo "capi VM ID: $capi_vmid"

qm clone "$capi_vmid" 8888 \
  --full \
  --name capi-base \
  --pool templates

qm set 8888 --cores 2
qm set 8888 --memory 1024
qm set 8888 --serial0 socket --vga serial0
qm set 8888 --cicustom "user=local:snippets/user-data-capi.mime"
qm set 8888 --ipconfig0 "ip=10.0.0.188/24,gw=10.0.0.1"
qm set 8888 --nameserver "${DNS_SERVER_IP} 8.8.8.8"
qm set 8888 --tags "base dns-self-register k8s cluster-api"

qm start 8888

