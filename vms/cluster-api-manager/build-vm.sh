#!/usr/bin/env bash
set -euo pipefail

export DNS_SERVER_IP=$1
export VM_ID=10000

qm shutdown $VM_ID || true
qm destroy  $VM_ID || true

qm clone 9999 $VM_ID \
  --name cluster-api-manager \
  --pool infra

qm resize $VM_ID scsi0 20G

qm set $VM_ID --cores 2
qm set $VM_ID --memory 2048
qm set $VM_ID --cicustom "user=local:snippets/user-data-cluster-api-manager.mime"
#qm set $VM_ID --ipconfig0 "ip=10.0.0.222/24,gw=10.0.0.1"
qm set $VM_ID --nameserver "${DNS_SERVER_IP} 8.8.8.8"
qm set $VM_ID --tags "auto-dns"

qm start $VM_ID

