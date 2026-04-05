#!/usr/bin/env bash
set -euo pipefail

export DNS_NODE_IP=$1
export VM_ID=777

qm shutdown $VM_ID || true
qm destroy  $VM_ID || true

qm clone 9999 $VM_ID \
  --name blank \
  --pool dev

qm set $VM_ID --cores 1
qm set $VM_ID --memory 1024
qm set $VM_ID --cicustom "user=local:snippets/user-data-blank.mime"
qm set $VM_ID --nameserver "${DNS_NODE_IP} 8.8.8.8"
#qm set $VM_ID --ipconfig0 "ip=10.0.0.77/24,gw=10.0.0.1" # Make this a static IP VM.
qm set $VM_ID --tags "blank"

qm start $VM_ID

