#!/usr/bin/env bash
set -euo pipefail

export DNS_SERVER_IP=$1
export VM_ID=100

qm shutdown $VM_ID || true
qm destroy  $VM_ID || true

qm clone 9999 $VM_ID \
  --name postgres \
  --pool dev

qm resize $VM_ID scsi0 100G

qm set $VM_ID --cores 4
qm set $VM_ID --memory 16384
qm set $VM_ID --scsihw virtio-scsi-single
qm set $VM_ID --cicustom "user=local:snippets/user-data-postgres.mime"
qm set $VM_ID --ipconfig0 "ip=10.0.0.100/24,gw=10.0.0.1"
qm set $VM_ID --nameserver "${DNS_SERVER_IP} 8.8.8.8"
qm set $VM_ID --tags "db postgres"

qm start $VM_ID

