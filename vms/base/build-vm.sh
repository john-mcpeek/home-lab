#!/usr/bin/env bash
set -euo pipefail

BASE_VM_ID=9999
FORCE_REBUILD=0

usage() {
  echo "Usage: $0 [--force-rebuild]"
  echo "  Create the base Ubuntu template (VM ${BASE_VM_ID})."
  echo "  Without --force-rebuild, skips if VM ${BASE_VM_ID} already exists."
  exit 1
}

for arg in "$@"; do
  case "$arg" in
    --force-rebuild) FORCE_REBUILD=1 ;;
    -h|--help) usage ;;
    *)
      echo "Unknown argument: $arg"
      usage
      ;;
  esac
done

# List VM IDs whose configs still reference the template base volume (linked clones).
list_linked_clones() {
  local template_id=$1
  local conf id
  shopt -s nullglob
  for conf in /etc/pve/qemu-server/*.conf; do
    id=$(basename "$conf" .conf)
    [[ "$id" == "$template_id" ]] && continue
    if grep -qE "base-${template_id}-disk|/${template_id}/base-" "$conf"; then
      echo "$id"
    fi
  done | sort -n | uniq
}

print_linked_clone_help() {
  local template_id=$1
  shift
  local deps=("$@")

  echo "ERROR: Base template VM ${template_id} cannot be destroyed while linked clones exist."
  if ((${#deps[@]})); then
    echo "Linked clone VM IDs: ${deps[*]}"
    if qm list &>/dev/null; then
      qm list | head -n 1 || true
      for id in "${deps[@]}"; do
        qm list | awk -v id="$id" '$1 == id {print}' || echo "  ${id}"
      done
    fi
  else
    echo "No linked-clone references found in /etc/pve/qemu-server/*.conf,"
    echo "but destroy still failed (storage may hold residual refs)."
  fi
  echo
  echo "Fix options:"
  echo "  1) Destroy dependents, then rebuild the template:"
  echo "       qm shutdown <id>; qm destroy <id>"
  echo "       # re-run with --force-rebuild"
  echo "  2) Keep the existing template (default: omit --force-rebuild)."
  echo "  3) From the repo root (DESTRUCTIVE — destroys lab VMs and rebuilds base):"
  echo "       ./init-proxmox.sh <PROXMOX_IP> --nuke-vms --force-rebuild-base"
}

stop_vm() {
  local vmid=$1
  qm shutdown "$vmid" || true
  # Force-stop if still running so destroy can proceed.
  if qm status "$vmid" 2>/dev/null | grep -qi running; then
    qm stop "$vmid" || true
  fi
}

if qm status "$BASE_VM_ID" &>/dev/null; then
  if [[ "$FORCE_REBUILD" -eq 0 ]]; then
    echo "VM ${BASE_VM_ID} already exists; skipping base template rebuild."
    echo "Pass --force-rebuild to destroy and recreate it."
    if ! qm config "$BASE_VM_ID" | grep -qE '^template:[[:space:]]*1'; then
      echo "WARNING: VM ${BASE_VM_ID} exists but is not a template (expected 'template: 1')."
    fi
    exit 0
  fi

  mapfile -t LINKED < <(list_linked_clones "$BASE_VM_ID")
  if ((${#LINKED[@]})); then
    print_linked_clone_help "$BASE_VM_ID" "${LINKED[@]}"
    exit 1
  fi

  echo "Force-rebuilding base template VM ${BASE_VM_ID}..."
  stop_vm "$BASE_VM_ID"
  if ! qm destroy "$BASE_VM_ID"; then
    mapfile -t LINKED < <(list_linked_clones "$BASE_VM_ID")
    print_linked_clone_help "$BASE_VM_ID" "${LINKED[@]}"
    echo "ERROR: qm destroy ${BASE_VM_ID} failed."
    exit 1
  fi
fi

wget -q -nc -P /root https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img

DDNS_SERVER=$(ip -4 addr show vmbr0 | grep inet | awk '{print $2}' | cut -d'/' -f1)
export DDNS_SERVER

# create a new VM with VirtIO SCSI controller
qm create "$BASE_VM_ID" --name base-auto-dns \
  --tags "base auto-dns ubuntu" \
  --nameserver "${DDNS_SERVER} 75.75.75.75" \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-single \
  --cpu cputype=host \
  --agent enabled=1 \
  --memory 2048 \
  --core 2 \
  --pool templates

# import the downloaded disk to local storage, attaching it as a SCSI drive
qm set "$BASE_VM_ID" --scsi0 local:0,ssd=1,discard=on,iothread=1,cache=none,import-from=/root/ubuntu-24.04-server-cloudimg-amd64.img
qm resize "$BASE_VM_ID" scsi0 10G

qm set "$BASE_VM_ID" --cicustom "user=local:snippets/user-data-base-auto-dns.mime"
qm set "$BASE_VM_ID" --ide2 local:cloudinit
qm set "$BASE_VM_ID" --boot order=scsi0
qm set "$BASE_VM_ID" --serial0 socket --vga serial0
qm set "$BASE_VM_ID" --ipconfig0 ip=dhcp
qm start "$BASE_VM_ID"
qm wait --timeout 360 "$BASE_VM_ID"
qm template "$BASE_VM_ID"
