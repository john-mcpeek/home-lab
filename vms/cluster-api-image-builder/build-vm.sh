#!/usr/bin/env bash

export DNS_SERVER_IP=$1

qm shutdown 222
qm destroy  222

qm clone 9999 222 \
  --name image-builder-builder \
  --pool infra

qm resize 222 scsi0 20G

qm set 222 --cores 2
qm set 222 --memory 4096
qm set 222 --cicustom "user=local:snippets/user-data-image-builder.mime"
qm set 222 --ipconfig0 "ip=10.0.0.222/24,gw=10.0.0.1"
qm set 222 --nameserver "${DNS_SERVER_IP} 8.8.8.8"
qm set 222 --tags "cluster-api image-builder-builder"

qm start 222

