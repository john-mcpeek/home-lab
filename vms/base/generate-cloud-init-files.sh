#!/usr/bin/env bash

function dns_setup() {
  # Path to the configuration file
  CONFIG_FILE="/etc/bind/keys/ddns.key"

  # Check if the file exists
  if [[ ! -f "$CONFIG_FILE" ]]; then
      echo "Error: Configuration file $CONFIG_FILE not found"
      exit 1
  fi

  # Extract the DDNS_KEY value using grep and sed
  DDNS_KEY=$(grep 'secret' "$CONFIG_FILE" | sed -n 's/.*secret "\(.*\)";/\1/p')
  export DDNS_KEY

  # Check if DDNS_KEY was found
  if [[ -z "$DDNS_KEY" ]]; then
      echo "Error: Could not extract DDNS_KEY from $CONFIG_FILE"
      exit 1
  fi

  # Output the extracted key
  echo "DDNS_KEY: $DDNS_KEY"

  NODE_IP=$(ip -4 addr show vmbr0 | grep inet | awk '{print $2}' | cut -d'/' -f1)
  export NODE_IP
  DDNS_SERVER=$NODE_IP
  export DDNS_SERVER

  envsubst '${DDNS_KEY} ${DDNS_SERVER}' < base/base-dns-self-register.yaml | tee generated/base-dns-self-register.yaml > /dev/null
  envsubst '${DDNS_KEY} ${NODE_IP}' < base/base-dns-register-dynamic.yaml | tee generated/base-dns-register-dynamic.yaml > /dev/null
  envsubst '${DDNS_KEY} ${NODE_IP}' < base/base-dns-register-static-ip.yaml | tee generated/base-dns-register-static-ip.yaml > /dev/null
}

function update_keys() {
  envsubst '${MY_PUBLIC_KEY} ${PROXMOX_ROOT_PUBLIC_KEY}' < base/base-cloud-init.yaml | tee generated/base-cloud-init.yaml > /dev/null
}

function static_ip_register() {
  cloud-init devel make-mime \
    -a generated/base-cloud-init.yaml:cloud-config \
    -a generated/base-dns-register-static-ip.yaml:cloud-config \
    -a base/base-shut-down.yaml:cloud-config \
    > generated/user-data-base-static-ip.mime
}

function dhcp_ip_register() {
  cloud-init devel make-mime \
    -a generated/base-cloud-init.yaml:cloud-config \
    -a generated/base-dns-register-dynamic.yaml:cloud-config \
    -a base/base-shut-down.yaml:cloud-config \
    > generated/user-data-base-dynamic-ip.mime
}

function dns_self_register() {
  cloud-init devel make-mime \
    -a generated/base-cloud-init.yaml:cloud-config \
    -a generated/base-dns-self-register.yaml:cloud-config \
    -a base/base-shut-down.yaml:cloud-config \
    > generated/user-data-base-dns-self-register.mime
    cloud-init schema --config-file generated/user-data-base-dns-self-register.mime --annotate
}

export MY_PUBLIC_KEY=$1

PROXMOX_ROOT_PUBLIC_KEY=$(cat /root/.ssh/id_rsa.pub)
export PROXMOX_ROOT_PUBLIC_KEY

mkdir -p generated

dns_setup
update_keys
dns_self_register
static_ip_register
dhcp_ip_register

# Copy generated cloud-init files to snippets.
cp -f generated/*.mime /var/lib/vz/snippets/
echo "Generated cloud init config moved to snippets"