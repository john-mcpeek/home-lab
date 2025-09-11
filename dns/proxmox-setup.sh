#!/usr/bin/env bash

function update_source_list() {
  # Turn off subscription ceph. Turn on no subscription ceph.
  CEPH_SOURCES="/etc/apt/sources.list.d/ceph.sources"
  if ! grep -q "Components: no-subscription" "$CEPH_SOURCES"; then
    echo "'Components: no-subscription' not found, adding no subscription ceph"
    echo "deb http://example.com/debian stable main" >> "$CEPH_SOURCES"
  cat proxmox/ceph-repo-update.txt | tee -a "$CEPH_SOURCES" > /dev/null
  else
    echo "'Components: no-subscription' found, no action needed."
  fi

  # Turn off subscription Proxmox.
  ENTERPRISE_PVE_SOURCES="/etc/apt/sources.list.d/pve-enterprise.sources"
  if ! grep -q "Enabled: false" "$ENTERPRISE_PVE_SOURCES"; then
    echo "'Enabled: false' not found, adding no subscription Proxmox"
    echo "Enabled: false" | tee -a "$ENTERPRISE_PVE_SOURCES" > /dev/null
  else
    echo "'Enabled: false' found, no action needed."
  fi

  # Turn on no-subscription Proxmox.
  cp proxmox/proxmox.sources /etc/apt/sources.list.d/
}

function update_packages() {
  apt update
  apt upgrade -y
  apt install -y bind9 bind9utils dnsutils \
    jq \
    vim \
    cloud-init \
    apparmor-utils
}

function configure_lab_dns_zone() {
  local proxmox_ip=$1

  # app armor stops bind from coming up, So I switched over to complain.
  aa-complain /usr/sbin/named

  tsig-keygen -a hmac-sha256 ddns-key | tee /etc/bind/ddns-key.conf >/dev/null
  chown root:bind /etc/bind/ddns-key.conf
  chmod 640 /etc/bind/ddns-key.conf

  # Apply DNS 'lab' zone config
  cp -f proxmox/named.conf.options /etc/bind/named.conf.options
  cp -f proxmox/named.conf.local /etc/bind/named.conf.local
  cp -f proxmox/lab.zone /var/lib/bind/lab.zone

  chown -R bind:bind /var/lib/bind
  chmod -R 775 /var/lib/bind

  named-checkzone lab /var/lib/bind/lab.zone
  named-checkconf
  systemctl restart bind9

  # Test DNS
  dig "@${proxmox_ip}" "$(hostname).lab"

  cp -f proxmox/resolv.conf /etc/resolv.conf
}

function update_tag_style() {
    # Check if machine name/IP is provided
    if [ -z "$1" ]; then
        echo "Error: Please provide the Proxmox machine name or IP as the first argument."
        return 1
    fi

    # Check if password is provided
    if [ -z "$2" ]; then
        echo "Error: Please provide the Proxmox machine password as the second argument."
        return 1
    fi

    # Variables
    PVE_HOST="$1"                  # Machine name or IP
    API_URL="https://${PVE_HOST}:8006/api2/json"
    USERNAME="root@pam"            # Change if using a different user
    PASSWORD="$2"  # Use env var or default (replace 'your_password')
    TAG_STYLE="shape=full;ordering=configuration"  # Your desired settings

    # Step 1: Authenticate to get ticket and CSRF token
    AUTH_RESPONSE=$(curl -s -k -d "username=${USERNAME}&password=${PASSWORD}" "${API_URL}/access/ticket")

    # Check if authentication was successful
    if ! echo "${AUTH_RESPONSE}" | jq -e '.data.ticket' > /dev/null; then
        echo "Error: Authentication failed. Check credentials or host."
        return 1
    fi

    # Extract ticket and CSRF token
    TICKET=$(echo "${AUTH_RESPONSE}" | jq -r '.data.ticket')
    CSRF_TOKEN=$(echo "${AUTH_RESPONSE}" | jq -r '.data.CSRFPreventionToken')

    # Step 2: Update tag style
    UPDATE_RESPONSE=$(curl -s -k \
        -b "PVEAuthCookie=${TICKET}" \
        -H "CSRFPreventionToken: ${CSRF_TOKEN}" \
        -d "tag-style=${TAG_STYLE}" \
        "${API_URL}/cluster/options")

    # Check if update was successful ({"data":null} with no message)
    if echo "${UPDATE_RESPONSE}" | jq -e '.data == null and .message == null' > /dev/null; then
        echo "Success: Tag style updated to shape=full and ordering=configuration on ${PVE_HOST}."
    else
        ERROR_MESSAGE=$(echo "${UPDATE_RESPONSE}" | jq -r '.message // "Unknown error"')
        echo "Error: Failed to update tag style: ${ERROR_MESSAGE}"
        echo "Full response: ${UPDATE_RESPONSE}"
        return 1
    fi
}

function create_pool() {
    # Check if machine name/IP is provided
    if [ -z "$1" ]; then
        echo "Error: Please provide the Proxmox machine name or IP as the first argument."
        return 1
    fi

    # Check if password is provided
    if [ -z "$2" ]; then
        echo "Error: Please provide the Proxmox machine password as the second argument."
        return 1
    fi

    # Check if pool name is provided
    if [ -z "$3" ]; then
        echo "Error: Please provide the Proxmox pool name as the third argument."
        return 1
    fi

    # Variables
    PVE_HOST="$1"                  # Machine name or IP
    API_URL="https://${PVE_HOST}:8006/api2/json"
    USERNAME="root@pam"            # Change if using a different user
    PASSWORD="$2"       # Replace with your actual password
    POOL_NAME="$3"                # Pool name
    POOL_COMMENT="$3 pool"

    # Step 1: Authenticate to get ticket and CSRF token
    AUTH_RESPONSE=$(curl -s -k -d "username=${USERNAME}&password=${PASSWORD}" "${API_URL}/access/ticket")

    # Check if authentication was successful
    if ! echo "${AUTH_RESPONSE}" | jq -e '.data.ticket' > /dev/null; then
        echo "Error: Authentication failed. Check credentials or host."
        return 1
    fi

    # Extract ticket and CSRF token
    TICKET=$(echo "${AUTH_RESPONSE}" | jq -r '.data.ticket')
    CSRF_TOKEN=$(echo "${AUTH_RESPONSE}" | jq -r '.data.CSRFPreventionToken')

    # Step 2: Create the pool
    CREATE_RESPONSE=$(curl -s -k \
        -b "PVEAuthCookie=${TICKET}" \
        -H "CSRFPreventionToken: ${CSRF_TOKEN}" \
        -d "poolid=${POOL_NAME}" \
        -d "comment=${POOL_COMMENT}" \
        "${API_URL}/pools")

    # Check if pool creation was successful
    if echo "${CREATE_RESPONSE}" | jq -e '.data == null and .message == null' > /dev/null; then
        echo "Success: Pool '${POOL_NAME}' created on ${PVE_HOST}."
    else
        ERROR_MESSAGE=$(echo "${CREATE_RESPONSE}" | jq -r '.message // "Unknown error"')
        echo "Error: Failed to create pool: ${ERROR_MESSAGE}"
        echo "Full response: ${CREATE_RESPONSE}"
    fi

    POOL_LIST=$(curl -s -k -b "PVEAuthCookie=${TICKET}" -H "CSRFPreventionToken: ${CSRF_TOKEN}" "${API_URL}/pools")
    echo "${POOL_LIST}"
}

function proxmox_miscellany() {
  echo "alias l='ls -alh --color'" >> /etc/bash.bashrc

  # Setup snippet directory
  mkdir -p /var/lib/vz/snippets
}

NODE_IP=$(ip -4 addr show vmbr0 | grep inet | awk '{print $2}' | cut -d'/' -f1)
export NODE_IP
export PASSWORD=$1

update_source_list
update_packages
configure_lab_dns_zone $NODE_IP
create_pool $NODE_IP $PASSWORD dev
create_pool $NODE_IP $PASSWORD uat
create_pool $NODE_IP $PASSWORD prod
create_pool $NODE_IP $PASSWORD templates
proxmox_miscellany

########################################################################################
# NOTE: Proxmox is free garbage. Some stuff doesn't work.
# Datacenter -> Tag Style Override -> edit -> Tree Shape: Full, Ordering: Configuration
#######################################################################################
# Error: Failed to update tag style: Method 'POST /cluster/options' not implemented
# Full response: {"message":"Method 'POST /cluster/options' not implemented","data":null}
#update_tag_style $NODE_IP $PASSWORD