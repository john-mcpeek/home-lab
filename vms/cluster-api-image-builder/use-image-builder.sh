#!/usr/bin/env bash
set -euo pipefail


capi_image_name=$(ssh "root@10.0.0.222" "cd /cluster-api && ./cluster-api-image-builder-builder/build-vm.sh ${PROXMOX_IP}")
capi_vmid=$(qm list | grep "$capi_image_name" | awk '{print $1}')