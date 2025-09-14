#!/usr/bin/env bash

export NODE_IP=$1

qm shutdown 777
qm destroy  777

qm clone 8888 777 \
  --name blank \
  --pool dev

qm set 777 --cores 1
qm set 777 --memory 1024
qm set 777 --cicustom "user=local:snippets/user-data-blank.mime"
qm set 777 --nameserver "${NODE_IP} 8.8.8.8"
qm set 777 --tags "blank"

qm start 777

