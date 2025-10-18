# Proxmox Home Lab Automation

Automated infrastructure setup for a Proxmox-based home lab with DNS, VM templates, PostgreSQL, and infrastructure components.

## Prerequisites

- **Proxmox VE 9.x** (required)
- Network: 10.0.0.0/24 subnet with vmbr0 bridge
- Storage: local-lvm storage configured
- SSH access to Proxmox host
- Ed25519 SSH key at `~/.ssh/id_ed25519`
- Ansible SSH key will be auto-generated if missing

## Quick Start

```bash
   ./init-proxmox.sh $PROXMOX_HOST_IP $PROXMOX_ROOT_PASSWORD $POSTGRES_PASSWORD
```

**Example:**
```bash
   ./init-proxmox.sh 10.0.0.10 myRootPassword myPostgresPassword
```

## What Gets Created

The initialization takes a few minutes and sets up:

### Infrastructure
- Proxmox subscription sources disabled
- Proxmox no-subscription repositories enabled
- SSH keys copied to Proxmox host
- Resource pools created: `infra`, `dev`, `uat`, `prod`, `templates`
- `image-builder@pve` user with API token for Cluster API

### DNS Server
- BIND9 DNS server configured on Proxmox host
- Proxmox acts as authoritative DNS provider for `.lab`
- `.lab` domain with dynamic DNS (DDNS) support
- TSIG-secured DNS updates

### Base VM Template (VM ID 9999)
- Ubuntu 24.04 cloud image
- QEMU guest agent enabled
- SSH keys for `john` and `ansible` users installed
- Auto-registers hostname with DNS on boot
- **Note:** The base template automatically shuts down after creation. This enables unattended builds.
  Clone the template and use a cloud-init "topper" script to override the shutdown behavior (see `blank` VM example).

### Example VMs

#### Blank VM (VM ID 777)
- Simple example in `dev` pool
- Demonstrates how to use base template with cloud-init topper
- 1 core, 1GB RAM, DHCP networking

#### Image Builder (VM ID 222)
- Cluster API image builder builder in `infra` pool
- 2 cores, 4GB RAM, 20GB disk
- Static IP: 10.0.0.222/24

#### PostgreSQL Server (VM ID 100)
- PostgreSQL 17 server in `dev` pool
- 4 cores, 16GB RAM, 100GB disk
- Static IP: 10.0.0.100/24
- **Note:** Commented out by default in `init-proxmox.sh` (line 33)

## Architecture

### Network Configuration

- **Subnet**: 10.0.0.0/24
- **Gateway**: 10.0.0.1
- **DNS**: Proxmox host IP (primary), 75.75.75.75 or 8.8.8.8 (fallback)
- **Bridge**: vmbr0

### Directory Structure

```
.
├── init-proxmox.sh              # Main initialization script
├── proxmox/
│   ├── proxmox-setup.sh         # Proxmox configuration
│   └── dns/                     # DNS zone files and BIND config
└── vms/
    ├── init-base.sh             # Base template creation
    ├── init-blank.sh            # Example Blank VM
    ├── init-postgres.sh         # PostgreSQL VM
    ├── init-capi-image-builder-builder.sh  # Image builder VM
    ├── base/                    # Base template files
    ├── blank/                   # Blank VM files
    ├── postgres/                # PostgreSQL VM files
    └── cluster-api-image-builder-builder/  # Image builder files
```

## Individual Component Setup

You can run individual components instead of the full initialization:

```bash

# Base template only
cd vms
./init-base.sh $PROXMOX_IP

# Blank VM only
cd vms
./init-blank.sh $PROXMOX_IP

# PostgreSQL VM
cd vms
./init-postgres.sh $PROXMOX_IP $POSTGRES_PASSWORD

# Image builder builder VM
cd vms
./init-capi-image-builder.sh $PROXMOX_IP
```

## VM Creation Pattern

All non k8s capi VMs clone from the base template (VM ID 9999):

```bash

# Clone template
qm clone 9999 <VM_ID> --name <VM_NAME> --pool <POOL>

# Configure resources
qm set <VM_ID> --cores <CORES>
qm set <VM_ID> --memory <MEMORY_MB>

# Optional: resize disk
qm resize <VM_ID> scsi0 <SIZE>G

# Set cloud-init topper
qm set <VM_ID> --cicustom "user=local:snippets/<your-cloud-init>.mime"

# Configure networking
qm set <VM_ID> --ipconfig0 "ip=10.0.0.<IP>/24,gw=10.0.0.1"
qm set <VM_ID> --nameserver "<DNS_IP> 8.8.8.8"

# Add tags
qm set <VM_ID> --tags "tag1,tag2"

# Start VM
qm start <VM_ID>
```

## DNS Testing

```bash

# Test forward lookup
dig @10.0.0.10 pve.lab

# Test reverse lookup
dig @10.0.0.10 -x 10.0.0.10
```

## SSH Access

```bash

# Personal user
ssh john@<VM_IP>

# Ansible user (key auto-generated during init-base.sh)
ssh -i ~/.ssh/ansible ansible@<VM_IP>
```

## Troubleshooting

### DNS Issues

```bash

# Check BIND status
systemctl status named

# Verify zone files
named-checkzone lab /etc/bind/zones/db.lab
named-checkzone 0.0.10.in-addr.arpa /etc/bind/zones/db.10.0.0

# Test DNS
dig @localhost pve.lab
```

### Base Template Auto-Shutdown

The base template is designed to shut down automatically after initial setup. This is expected behavior. To use the template, clone it and override the shutdown with a cloud-init topper (see `vms/blank/generate-cloud-init-files.sh`).

### Cloud-init Not Applying

```bash

# Verify snippet exists
ls -la /var/lib/vz/snippets/

# Check VM config
qm config <VM_ID>

# Update cloud-init
qm cloudinit update <VM_ID>
```

## Future Components

See `home-lab-components.md` for planned additions:
- HCP Vault
- Artifactory
- HA Kubernetes
- Ceph Storage
- Grafana/Prometheus
- ArgoCD
- Kiali/Thanos
- SSO