 # CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Proxmox-based home lab automation repository that sets up a complete infrastructure including DNS, VM templates, PostgreSQL database, and Kubernetes clusters using Proxmox virtualization.

## Key Commands

### Initial Setup
```bash

# Main initialization - sets up entire Proxmox environment
./init-proxmox.sh $PROXMOX_HOST_IP $PROXMOX_ROOT_PASSWORD $POSTGRES_PASSWORD

# Individual component initialization (called by init-proxmox.sh)
./vms/init-base.sh $PROXMOX_IP          # Creates base VM template
./vms/init-blank.sh $PROXMOX_IP         # Creates blank VM example
./vms/init-kubespray.sh $PROXMOX_IP     # Sets up Kubernetes VMs
./vms/init-postgres.sh $PROXMOX_IP $POSTGRES_PASSWORD  # Sets up PostgreSQL VM
```

### File Conversion (Important)
```bash

# Convert all files from DOS to Unix format before deployment
find . -type f -exec dos2unix {} \;
```

### DNS Validation Commands
```bash
# Check DNS configuration (built into dns/proxmox-setup.sh)
named-checkconf
named-checkzone lab /var/cache/bind/db.lab

# Test DNS resolution
dig @localhost pve.lab
dig @localhost -x 10.0.0.10  # Test reverse DNS
```

## Architecture

### Directory Structure and Purpose

- **`dns/`**: DNS server configuration for the lab domain
  - Sets up BIND9 DNS with dynamic DNS (DDNS) support
  - Creates `.lab` domain with reverse DNS
  - Configures TSIG keys for secure dynamic updates

- **`vms/`**: VM provisioning scripts organized by type
  - **`base/`**: Base template creation with cloud-init, qemu-guest-agent, and SSH keys
  - **`blank/`**: Example VM using the base template `(topper)`
  - **`postgres/`**: PostgreSQL 17 with pgvector extension
  - **`kubespray/`**: Kubernetes cluster VMs configured for Kubespray deployment

- **`inventory/`**: Ansible inventory for Kubernetes nodes
  - Defines control plane and worker nodes with their IPs, resources, and roles

### VM Management Architecture

1. **Base Template System**: Creates Ubuntu 24.04 template (VM ID 9999) with:
   - Cloud-init pre-configured with user SSH keys (john and ansible users)
   - QEMU guest agent for Proxmox integration
   - Dynamic DNS self-registration capability
   - Auto-shutdown behavior (requires cloud-init `topper`, see: )
     - The auto-shutdown behavior is for automating the template creation. This feature
       is designed to eliminate manual intervention.
     - This requires using a `topper` cloud-init to override the auto-shutdown behavior.
       example: The `blank` VM.

2. **VM Cloning Pattern**: All VMs clone from base template and apply:
   - Custom cloud-init user data via MIME snippets
   - Static IP configuration in 10.0.0.0/24 network
   - Resource allocation (CPU cores, RAM) from inventory
   - Pool assignment (dev, uat, prod, templates)

3. **Network Configuration**:
   - Bridge: vmbr0
   - Network: 10.0.0.0/24
   - Gateway: 10.0.0.1
   - DNS: Proxmox host (primary), 75.75.75.75 or 8.8.8.8 (fallback)

### Proxmox Configuration

- Disables subscription repositories and enables no-subscription repos
- Creates resource pools: dev, uat, prod, templates
- Configures local DNS server as authoritative for `.lab` domain
- Sets up cloud-init snippets storage at `/var/lib/vz/snippets`

### Kubernetes Architecture (Kubespray)

- **Control Plane**: 3 nodes (10.0.0.141-143) with 3 cores, 4GB RAM each
- **Workers**: 4 nodes (10.0.0.151-154) with 4 cores, 8GB RAM each
- VM IDs match last octet of IP addresses for easy identification
- Ansible inventory defines etcd, control plane, and worker node groups

## Important Implementation Details

- All scripts use `set -euo pipefail` for error handling
- SSH keys are automatically deployed from `~/.ssh/id_ed25519.pub` and `~/.ssh/ansible.pub`
- VMs use VirtIO SCSI controllers with SSD emulation and discard support
- Cloud-init MIME multipart format is used for complex configurations
- AppArmor is set to complain mode for BIND9 to prevent startup issues
- VM templates must be converted to templates after initial configuration