#!/usr/bin/env bash

function dns_setup() {
  local CLOUD_INIT_DNS_SELF_REGISTER_YAML="$1"

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

  envsubst '${DDNS_KEY} ${DDNS_SERVER}' < "${CLOUD_INIT_DNS_SELF_REGISTER_YAML}" | tee generated/base-dns-self-register.yaml > /dev/null
}