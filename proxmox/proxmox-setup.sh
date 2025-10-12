#!/usr/bin/env bash

function update_source_list() {
  echo "update_source_list"

  # Turn off subscription ceph. Turn on no subscription ceph.
  local CEPH_SOURCES="/etc/apt/sources.list.d/ceph.sources"
  if ! grep -q "Components: no-subscription" "$CEPH_SOURCES"; then
    echo "'Components: no-subscription' not found, adding no subscription ceph"
    echo "deb http://example.com/debian stable main" >> "$CEPH_SOURCES"
  cat dns/ceph-repo-update.txt | tee -a "$CEPH_SOURCES" > /dev/null
  else
    echo "'Components: no-subscription' found, no action needed."
  fi

  # Turn off subscription Proxmox.
  local ENTERPRISE_PVE_SOURCES="/etc/apt/sources.list.d/pve-enterprise.sources"
  if ! grep -q "Enabled: false" "$ENTERPRISE_PVE_SOURCES"; then
    echo "'Enabled: false' not found, adding no subscription Proxmox"
    echo "Enabled: false" | tee -a "$ENTERPRISE_PVE_SOURCES" > /dev/null
  else
    echo "'Enabled: false' found, no action needed."
  fi

  # Turn on no-subscription Proxmox.
  cp dns/proxmox.sources /etc/apt/sources.list.d/

  echo "update_source_list - complete"
}

function update_packages() {
  echo "update_packages"

  apt update
  apt upgrade -y
  apt install -y bind9 bind9-utils dnsutils \
    jq \
    vim \
    snapd \
    cloud-init \
    apparmor-utils && \
  apt autoremove -y && \
  apt clean

  echo "update_packages - complete"
}

function configure_lab_dns_zone() {
  echo "configure_lab_dns_zone"

  local PROXMOX_IP=$1

  mkdir -p generated/dns
  envsubst '${PROXMOX_IP}' < dns/db.10.0.0 | tee generated/dns/db.10.0.0 > /dev/null
  envsubst '${PROXMOX_IP}' < dns/db.lab | tee generated/dns/db.lab > /dev/null
  envsubst '${PROXMOX_IP}' < dns/resolv.conf | tee generated/dns/resolv.conf > /dev/null

  # app armor stops bind from coming up, So I switched over to complain.
  aa-complain /usr/sbin/named

  # Layout for clarity
  mkdir -p /etc/bind/zones /etc/bind/keys
  chown -R root:bind /etc/bind/keys
  chmod 750 /etc/bind/keys
  chown -R bind:bind /etc/bind/zones
  chmod 775 /var/lib/bind

  # Generate a TSIG key for DDNS
  tsig-keygen -a hmac-sha256 ddns-key | tee /etc/bind/keys/ddns.key >/dev/null
  chown root:bind /etc/bind/keys/ddns.key
  chmod 640 /etc/bind/keys/ddns.key

  # Apply DNS 'lab' zone config
  cp -f dns/named.conf.options  /etc/bind/named.conf.options
  cp -f dns/named.conf.local    /etc/bind/named.conf.local
  cp -f generated/dns/db.lab    /etc/bind/zones/db.lab
  cp -f generated/dns/db.10.0.0 /etc/bind/zones/db.10.0.0

  named-checkconf
  named-checkzone lab /etc/bind/zones/db.lab
  named-checkzone 0.0.10.in-addr.arpa /etc/bind/zones/db.10.0.0

  systemctl enable --quiet --now named
  systemctl reload named
  systemctl status named

  # Test DNS
  echo "expect: ${PROXMOX_IP}"
  dig "@${PROXMOX_IP}" "$(hostname).lab" +short
  # expect: 10.0.0.10
  echo "expect: $(hostname).lab"
  dig "@${PROXMOX_IP}" -x "${PROXMOX_IP}" +short
  # expect: pve.lab.

  cp -f generated/dns/resolv.conf /etc/resolv.conf

  echo "configure_lab_dns_zone - complete"
}

function update_tag_styles() {
  echo "update_tag_styles ********"

  # Update tag style if not set.
  local PVE_DATACENTER_CONFIG="/etc/pve/datacenter.cfg"
  if ! grep -q "tag-style: ordering=config,shape=full" "$PVE_DATACENTER_CONFIG"; then
    echo "'tag-style' set"
    echo "tag-style: ordering=config,shape=full" >> "$PVE_DATACENTER_CONFIG"
  else
    echo "'tag-style' found, no action needed."
  fi

  echo "update_tag_styles - complete"
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

  echo "create_pool '$3' ********"

  # Variables
  local PVE_HOST="$1"           # Machine name or IP
  local PASSWORD="$2"           # Replace with your actual password
  local POOL_NAME="$3"          # Pool name
  local POOL_COMMENT="$POOL_NAME pool"
  local API_URL="https://${PVE_HOST}:8006/api2/json"
  local USER_NAME="root@pam"    # Change if using a different user

  # Step 1: Authenticate to get ticket and CSRF token
  local AUTH_RESPONSE
  AUTH_RESPONSE=$(curl -s -k -d "username=${USER_NAME}&password=${PASSWORD}" "${API_URL}/access/ticket")

  # Check if authentication was successful
  if ! echo "${AUTH_RESPONSE}" | jq -e '.data.ticket' > /dev/null; then
      echo "Error: Authentication failed. Check credentials or host."
      return 1
  fi

  # Extract ticket and CSRF token
  local TICKET
  TICKET=$(echo "${AUTH_RESPONSE}" | jq -r '.data.ticket')
  local CSRF_TOKEN
  CSRF_TOKEN=$(echo "${AUTH_RESPONSE}" | jq -r '.data.CSRFPreventionToken')

  # Step 2: Create the pool
  local CREATE_RESPONSE
  CREATE_RESPONSE=$(curl -s -k \
      -b "PVEAuthCookie=${TICKET}" \
      -H "CSRFPreventionToken: ${CSRF_TOKEN}" \
      -d "poolid=${POOL_NAME}" \
      -d "comment=${POOL_COMMENT}" \
      "${API_URL}/pools")

  # Check if pool creation was successful
  if echo "${CREATE_RESPONSE}" | tr -d '\n' | jq -e '.data == null and .message == null' > /dev/null; then
      echo "Success: Pool '${POOL_NAME}' created on ${PVE_HOST}."
  else
      if [[ "$CREATE_RESPONSE" =~ "already exists" ]]; then
        echo "The '$POOL_NAME' pool already exists."
      else
        local ERROR_MESSAGE
        ERROR_MESSAGE=$(echo "${CREATE_RESPONSE}" | jq -r '.message // "Unknown error"')
        echo "Error: Failed to create pool: ${ERROR_MESSAGE}"
        echo "Full response: ${CREATE_RESPONSE}"
      fi
  fi

  echo "create_pool $3 - complete"
}

function add_image_builder_user() {
  echo "add_image_builder_user ********"

  # On Proxmox server, create everything from scratch
  local PVE_HOST="$1"
  local USER_NAME="image-builder"
  local TOKEN_NAME="capi"
  local PASSWORD
  PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)

  # Create user
  local IMAGE_BUILDER_USER
  IMAGE_BUILDER_USER=$(pveum user list --output-format json | jq '.[] | select(.userid == "image-builder@pve")')
  if [ -z "$IMAGE_BUILDER_USER" ]; then
    pveum user add "${USER_NAME}@pve" --password "${PASSWORD}"
    echo "user: ${USER_NAME}@pve added"
  else
    echo "user: ${USER_NAME}@pve existed. No action taken"
  fi

  local IMAGE_BUILDER_ROLE
  IMAGE_BUILDER_ROLE=$(pveum role list --output-format json | jq '.[] | select(.roleid == "image-builder")')
  if [ -z "$IMAGE_BUILDER_ROLE" ]; then
    pveum role add "${USER_NAME}" --privs "VM.GuestAgent.Unrestricted, VM.GuestAgent.FileRead, Sys.AccessNetwork, VM.Audit, Sys.Syslog, VM.GuestAgent.Audit, Sys.Incoming, Datastore.AllocateTemplate, VM.Snapshot.Rollback, VM.Console, VM.Snapshot, Sys.Console, VM.GuestAgent.FileWrite, VM.Config.HWType, VM.Clone, Datastore.Allocate, VM.Replicate, VM.Config.Disk, VM.Config.Network, VM.GuestAgent.FileSystemMgmt, VM.Backup, Datastore.AllocateSpace, VM.PowerMgmt, VM.Allocate, SDN.Allocate, VM.Config.CDROM, Sys.Modify, VM.Config.CPU, Datastore.Audit, VM.Config.Cloudinit, Sys.Audit, Sys.PowerMgmt, SDN.Use, VM.Config.Options, SDN.Audit, VM.Config.Memory, VM.Migrate, Group.Allocate, Mapping.Audit, Mapping.Modify, Mapping.Use, Permissions.Modify, Pool.Allocate, Pool.Audit, Realm.Allocate, Realm.AllocateUser, User.Modify"
    echo "role: ${USER_NAME} added"
  else
    echo "role: ${USER_NAME} existed. No action taken"
  fi

  # Give permissions
  local IMAGE_BUILDER_ACL
  IMAGE_BUILDER_ACL=$(pveum acl list --output-format json | jq '.[] | select(.ugid == "image-builder@pve")')
  if [ -z "$IMAGE_BUILDER_ACL" ]; then
    pveum acl modify / -user "${USER_NAME}@pve" -role "${USER_NAME}"
    echo "acl for user: ${USER_NAME}@pve modified"
  else
    echo "acl for user ${USER_NAME}@pve existed. No action taken"
  fi

  # Create token
  local IMAGE_BUILDER_TOKEN
  IMAGE_BUILDER_TOKEN=$(pveum user token list "${USER_NAME}@pve" --output-format json | jq '.[] | select(.tokenid == "capi")')
  if [ -z "$IMAGE_BUILDER_TOKEN" ]; then
    local TOKEN
    TOKEN=$(pveum user token add "${USER_NAME}@pve" "${TOKEN_NAME}" --privsep 0 --output-format json | jq -r '.value')
    echo "token: ${TOKEN_NAME} added for user: ${USER_NAME}@pve"
  else
    if [ -f "$HOME/image-builder.token" ]; then
      echo "token: ${TOKEN_NAME} existed for user ${USER_NAME}@pve. No action taken"
    else
      echo "Token exists. We can't get that value. So, we delete it and create a new one."
      pveum user token delete "${USER_NAME}@pve" "${TOKEN_NAME}"
      local TOKEN
      TOKEN=$(pveum user token add "${USER_NAME}@pve" "${TOKEN_NAME}" --privsep 0 --output-format json | jq -r '.value')
      echo "token: ${TOKEN_NAME} added for user: ${USER_NAME}@pve"
    fi
  fi

  # Test the token
  curl -s -k -H "Authorization: PVEAPIToken=${USER_NAME}@pve\!${TOKEN_NAME}=${TOKEN}" \
    "https://${PVE_HOST}:8006/api2/json/version"

  # If successful, use these in your environment:
  if [ -z "$IMAGE_BUILDER_TOKEN" ]; then
    echo "Creating image-builder user token file (~/image-builder.token)"
    echo "PROXMOX_USER_NAME=${USER_NAME}@pve!${TOKEN_NAME}" > ~/image-builder.token
    echo "PROXMOX_TOKEN=${TOKEN}" >> ~/image-builder.token
    echo "image-builder.token set"
  fi

  echo "add_image_builder_user - complete"
}

function proxmox_miscellany() {
  echo "proxmox_miscellany ********"

  echo "alias l='ls -alh --color'" >> /etc/bash.bashrc

  # Setup snippet directory
  mkdir -p /var/lib/vz/snippets

  echo "proxmox_miscellany - complete"
}

PROXMOX_IP=$(ip -4 addr show vmbr0 | grep inet | awk '{print $2}' | cut -d'/' -f1)
export PROXMOX_IP
export PASSWORD=$1

update_source_list
update_packages
update_tag_styles
add_image_builder_user "$PROXMOX_IP"
configure_lab_dns_zone "$PROXMOX_IP"
create_pool "$PROXMOX_IP" "$PASSWORD" infra
create_pool "$PROXMOX_IP" "$PASSWORD" dev
create_pool "$PROXMOX_IP" "$PASSWORD" uat
create_pool "$PROXMOX_IP" "$PASSWORD" prod
create_pool "$PROXMOX_IP" "$PASSWORD" templates
proxmox_miscellany
