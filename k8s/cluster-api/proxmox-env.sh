#!/usr/bin/env bash

export PROXMOX_URL=https://${PROXMOX_IP}:8006/api2/json
export PROXMOX_TOKEN=image-builder@pve!capi
export PROXMOX_SECRET=${PROXMOX_TOKEN}

# The node that hosts the VM template to be used to provision VMs
export PROXMOX_SOURCENODE="pve"
# The template VM ID used for cloning VMs
export TEMPLATE_VMID=101
# The ssh authorized keys used to ssh to the machines.
export VM_SSH_KEYS="id_ed25519"
# The IP address used for the control plane endpoint
export CONTROL_PLANE_ENDPOINT_IP=10.0.0.39
# The IP ranges for Cluster nodes
export NODE_IP_RANGES="[10.0.0.40-10.0.0.50]"
# The gateway for the machines network-config.
export GATEWAY="10.0.0.1"
# Subnet Mask in CIDR notation for your node IP ranges
export IP_PREFIX=24
# The Proxmox network device for VMs
export BRIDGE="vmbr0"
# The dns nameservers for the machines network-config.
export DNS_SERVERS="[10.0.0.10,8.8.8.8]"
# The Proxmox nodes used for VM deployments
export ALLOWED_NODES="[pve]"
