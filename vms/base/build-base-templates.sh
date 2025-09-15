#!/usr/bin/env bash

wget -nc -P /root https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img

qm shutdown 9999
qm destroy 9999

DDNS_SERVER=$(ip -4 addr show vmbr0 | grep inet | awk '{print $2}' | cut -d'/' -f1)
export DDNS_SERVER

# create a new VM with VirtIO SCSI controller
qm create 9999 --name base-dns-self-register \
  --tags "base ubuntu dns-self-register" \
  --nameserver "${DDNS_SERVER} 75.75.75.75" \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-single \
  --cpu cputype=host \
  --agent enabled=1 \
  --memory 2048 \
  --core 2 \
  --pool templates

# import the downloaded disk to the local-lvm storage, attaching it as a SCSI drive
qm set 9999 --scsi0 local-lvm:0,ssd=1,discard=on,iothread=1,cache=none,import-from=/root/ubuntu-24.04-server-cloudimg-amd64.img
qm resize 9999 scsi0 10G

qm set 9999 --cicustom "user=local:snippets/user-data-base-dns-self-register.mime"
qm set 9999 --ide2 local-lvm:cloudinit
qm set 9999 --boot order=scsi0
qm set 9999 --serial0 socket --vga serial0
qm set 9999 --ipconfig0 ip=dhcp
qm start 9999
qm wait --timeout 360 9999
qm template 9999