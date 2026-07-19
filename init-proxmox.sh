#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 PROXMOX_IP [--force-rebuild-base] [--nuke-vms]"
    echo "Description: Set up Proxmox host + lab VMs. Passwords from ./root-password and ./postgres-password."
    echo "  --force-rebuild-base  Recreate base template VM 9999 even if it already exists."
    echo "  --nuke-vms            Destroy known lab VMs (777, 100, 10000) and any linked clones of 9999 first."
    echo "                        Required together with --force-rebuild-base when linked clones still exist."
    echo "Example: $0 10.0.0.10"
    echo "Example: $0 10.0.0.10 --force-rebuild-base"
    echo "Example: $0 10.0.0.10 --nuke-vms --force-rebuild-base"
    exit 1
}

if [ $# -eq 0 ]; then
    usage
fi

PROXMOX_IP=""
FORCE_REBUILD_BASE=0
NUKE_VMS=0

for arg in "$@"; do
  case "$arg" in
    --force-rebuild-base) FORCE_REBUILD_BASE=1 ;;
    --nuke-vms) NUKE_VMS=1 ;;
    -h|--help) usage ;;
    *)
      if [ -z "$PROXMOX_IP" ]; then
        PROXMOX_IP=$arg
      else
        echo "Unknown argument: $arg"
        usage
      fi
      ;;
  esac
done

if [ -z "$PROXMOX_IP" ]; then
  usage
fi

if [ ! -f ./root-password ]; then
    echo "Error: ./root-password file not found. Create it with the Proxmox root password."
    exit 1
fi

if [ ! -f ./postgres-password ]; then
    echo "Error: ./postgres-password file not found. Create it with the Postgres password."
    exit 1
fi

export PROXMOX_IP
PROXMOX_PASSWORD=$(cat ./root-password)
export PROXMOX_PASSWORD
POSTGRES_PASSWORD=$(cat ./postgres-password)
export POSTGRES_PASSWORD

if ! command -v sshpass &>/dev/null; then
    sudo apt-get install -y sshpass
fi
ssh-keygen -R "${PROXMOX_IP}" || true
ssh-keygen -F "${PROXMOX_IP}" &>/dev/null || ssh-keyscan -H "${PROXMOX_IP}" >> ~/.ssh/known_hosts
sshpass -p "${PROXMOX_PASSWORD}" ssh-copy-id -i ~/.ssh/id_ed25519 "root@${PROXMOX_IP}"

# Clean up, just in case.
ssh "root@${PROXMOX_IP}" "rm -rf proxmox k8s vms"
find . -type f -not -path '*/.*/*' -exec dos2unix {} \;

scp -r proxmox/  k8s/ vms/ "root@${PROXMOX_IP}":~/

# Setup proxmox
ssh "root@${PROXMOX_IP}" "cd proxmox && ./proxmox-setup.sh ${PROXMOX_PASSWORD}"

# Generate SHA-512 hash of the root password on Proxmox and update answer.toml in place
ssh "root@${PROXMOX_IP}" "
    if ! command -v mkpasswd &>/dev/null; then
        apt install -y whois
    fi
    HASH=\$(mkpasswd -m sha-512 '${PROXMOX_PASSWORD}')
    sed -i \"s|^root-password-hashed = .*|root-password-hashed = \\\"\${HASH}\\\"|\" ~/proxmox/auto-install/answer.toml
"

# Optional: tear down lab VMs (and linked clones of the base template) before rebuilds.
if [ "$NUKE_VMS" -eq 1 ]; then
  echo "##########################################################"
  echo "WARNING: --nuke-vms — destroying known lab VMs and linked clones of template 9999"
  ssh "root@${PROXMOX_IP}" 'bash -s' <<'EOF'
set -euo pipefail
TEMPLATE_ID=9999
KNOWN_VMS=(777 100 10000)

stop_and_destroy() {
  local vmid=$1
  if ! qm status "$vmid" &>/dev/null; then
    return 0
  fi
  echo "Destroying VM ${vmid}..."
  qm shutdown "$vmid" || true
  if qm status "$vmid" 2>/dev/null | grep -qi running; then
    qm stop "$vmid" || true
  fi
  qm destroy "$vmid"
}

declare -A to_destroy=()
for id in "${KNOWN_VMS[@]}"; do
  to_destroy["$id"]=1
done

shopt -s nullglob
for conf in /etc/pve/qemu-server/*.conf; do
  id=$(basename "$conf" .conf)
  [[ "$id" == "$TEMPLATE_ID" ]] && continue
  if grep -qE "base-${TEMPLATE_ID}-disk|/${TEMPLATE_ID}/base-" "$conf"; then
    to_destroy["$id"]=1
  fi
done

for id in "${!to_destroy[@]}"; do
  stop_and_destroy "$id"
done

echo "Nuke of dependents complete."
EOF
fi

# Setup VMs
cd vms
BASE_ARGS=("${PROXMOX_IP}")
if [ "$FORCE_REBUILD_BASE" -eq 1 ]; then
  BASE_ARGS+=(--force-rebuild)
fi
./init-base.sh "${BASE_ARGS[@]}"
./init-blank.sh "${PROXMOX_IP}"
./init-postgres.sh "${PROXMOX_IP}" "${POSTGRES_PASSWORD}"
./init-capi-manager.sh "${PROXMOX_IP}"
