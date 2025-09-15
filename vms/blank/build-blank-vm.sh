#!/usr/bin/env bash

export NODE_IP=$1

qm shutdown 777
qm destroy  777

qm clone 9999 777 \
  --name blank \
  --pool dev

qm set 777 --cores 1
qm set 777 --memory 1024
qm set 777 --cicustom "user=local:snippets/user-data-blank.mime"
qm set 777 --nameserver "${NODE_IP} 8.8.8.8"
#qm set 777 --ipconfig0 "ip=10.0.0.77/24,gw=10.0.0.1"
qm set 777 --tags "blank"

qm start 777

#qm shutdown 888
#qm destroy  888
#
#qm clone 9999 888 \
#  --name blank \
#  --pool dev
#
#qm set 888 --cores 1
#qm set 888 --memory 1024
#qm set 888 --cicustom "user=local:snippets/user-data-blank.mime"
#qm set 888 --nameserver "${NODE_IP} 8.8.8.8"
#qm set 888 --ipconfig0 "ip=10.0.0.88/24,gw=10.0.0.1"
#qm set 888 --tags "blank2"
#
#qm start 888

