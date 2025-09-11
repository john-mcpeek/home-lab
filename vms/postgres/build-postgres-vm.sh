#!/usr/bin/env bash

qm shutdown 100
qm destroy  100

qm clone 9999 100 \
  --name postgres \
  --pool dev

qm set 100 --cores 8
qm set 100 --memory 32768
qm set 100 --scsihw virtio-scsi-single
qm set 100 --scsi1 local-lvm:100,ssd=1,discard=on,iothread=1,cache=none
qm set 100 --scsi2 local-lvm:32,ssd=1,discard=on,iothread=1,cache=none
qm set 100 --cicustom "user=local:snippets/user-data-postgres.mime"
qm set 100 --sshkey ~/.ssh/id_rsa.pub
qm set 100 --ipconfig0 "ip=10.0.0.100/24,gw=10.0.0.1"
qm set 100 --nameserver "10.0.0.10 8.8.8.8"
qm set 100 --tags postgres

qm start 100

