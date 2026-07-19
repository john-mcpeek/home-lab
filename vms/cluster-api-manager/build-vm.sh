#!/usr/bin/env bash
set -euo pipefail

export DNS_SERVER_IP=$1
export VM_ID=10000

if qm status "$VM_ID" &>/dev/null; then
  qm shutdown "$VM_ID" || true
  if qm status "$VM_ID" 2>/dev/null | grep -qi running; then
    qm stop "$VM_ID" || true
  fi
  qm destroy "$VM_ID"
fi

# Full clone so the base template (9999) can be replaced without tearing down this VM.
qm clone 9999 "$VM_ID" \
  --name cluster-api-manager \
  --full \
  --pool infra

qm resize "$VM_ID" scsi0 20G

qm set "$VM_ID" --cores 2
qm set "$VM_ID" --memory 3072
qm set "$VM_ID" --cicustom "user=local:snippets/user-data-cluster-api-manager.mime"
#qm set $VM_ID --ipconfig0 "ip=10.0.0.222/24,gw=10.0.0.1"
qm set "$VM_ID" --nameserver "${DNS_SERVER_IP} 8.8.8.8"
qm set "$VM_ID" --tags "auto-dns"

qm start "$VM_ID"
