 # CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Proxmox-based home lab automation repository that sets up a complete infrastructure including DNS, VM templates, PostgreSQL database, and Kubernetes clusters using Proxmox virtualization.

## Key Commands

### Initial Setup
```bash

# Main initialization - passwords from ./root-password and ./postgres-password
./init-proxmox.sh $PROXMOX_HOST_IP
./init-proxmox.sh $PROXMOX_HOST_IP --force-rebuild-base   # recreate template 9999
./init-proxmox.sh $PROXMOX_HOST_IP --nuke-vms --force-rebuild-base  # wipe lab VMs + base

# Individual component initialization (called by init-proxmox.sh)
./vms/init-base.sh $PROXMOX_IP                 # Creates base VM template (skips if 9999 exists)
./vms/init-base.sh $PROXMOX_IP --force-rebuild # Force recreate template
./vms/init-blank.sh $PROXMOX_IP                # Creates blank VM example (full clone)
./vms/init-postgres.sh $PROXMOX_IP $POSTGRES_PASSWORD  # Sets up PostgreSQL VM (full clone)
./vms/init-capi-manager.sh $PROXMOX_IP         # Cluster API manager (full clone)
```

### DNS Validation Commands
```bash

# Test DNS resolution
dig @localhost pve.lab
dig @localhost -x 10.0.0.10  # Test reverse DNS
```

## Architecture

### Directory Structure and Purpose

- **`proxmox/`**: Scripts and config run on the Proxmox host itself
  - `proxmox-setup.sh` — installs packages, configures BIND9, creates pools, adds the `image-builder` user
  - **`proxmox/dns/`**: BIND9 config templates, zone files, AppArmor local override (`apparmor-named-local`), and systemd drop-in for named

- **`vms/`**: VM provisioning — all `init-*.sh` scripts run **locally** and SSH/SCP into Proxmox
  - Each VM type has: `generate-cloud-init-files.sh` (generates MIME snippets), `build-vm.sh` (creates/clones the VM via `qm`)
  - **`base/`**: Ubuntu 24.04 base template (VM ID 9999) with QEMU guest agent, SSH keys, DDNS self-registration, and auto-shutdown
  - **`blank/`**: Example VM cloned from base, uses a `topper` cloud-init to cancel the auto-shutdown
  - **`postgres/`**: PostgreSQL 17 + pgvector
  - **`cluster-api-manager/`**: Bootstrap host for Cluster API

- **`k8s/cluster-api/`**: Cluster API + CAPMOX (Cluster API Provider for Proxmox) setup scripts and kubeconfig

### VM Management Architecture

**Execution model**: `init-proxmox.sh` and `init-*.sh` run on the local machine. They `scp` files to Proxmox then `ssh` in to execute. `proxmox-setup.sh` itself is run on Proxmox via `cd proxmox && ./proxmox-setup.sh`.

**Cloud-init generation pattern** (two phases, both run on Proxmox):
1. `generate-cloud-init-files.sh` — substitutes env vars into YAML templates via `envsubst`, then assembles MIME multipart files with `cloud-init devel make-mime`, outputs to `generated/`
2. Generated `.mime` files are copied to `/var/lib/vz/snippets/` so Proxmox can attach them via `--cicustom`

**Base template auto-shutdown**: The base template cloud-init includes `base-shut-down.yaml` which powers off the VM after first boot (enabling `qm template` to convert it unattended). VMs that should stay running (e.g. `blank`) include a `topper` cloud-config that overrides the shutdown.

**VM Cloning Pattern**: Durable VMs full-clone from base template (9999) with `qm clone ... --full` and apply:
- Custom cloud-init user data via MIME snippets
- Static IP configuration in 10.0.0.0/24 network
- Resource allocation (CPU cores, RAM) per VM type
- Pool assignment (dev, uat, prod, templates)

**Base template rebuild safety** (`vms/base/build-vm.sh`):
- Default: if VM 9999 already exists, skip recreate (idempotent re-runs)
- `--force-rebuild` (via `./init-base.sh IP --force-rebuild` or `./init-proxmox.sh IP --force-rebuild-base`): destroy and recreate only when no linked clones reference `base-9999-disk`
- Destroy failures are not ignored; scripts list dependent VM IDs and how to fix
- `./init-proxmox.sh IP --nuke-vms` destroys known lab VMs (777, 100, 10000) and any linked clones of 9999 before VM setup

**Network Configuration**:
- Bridge: vmbr0
- Network: 10.0.0.0/24
- Gateway: 10.0.0.1
- DNS: Proxmox host (primary), 75.75.75.75 (fallback)

### Proxmox Configuration

- Disables subscription Ceph/PVE repos, enables no-subscription repos
- Creates resource pools: dev, uat, prod, templates
- Configures BIND9 as authoritative for `.lab` domain with DDNS (TSIG key at `/etc/bind/keys/ddns.key`)
- Static zone files in `/etc/bind/`, writable journal/zone files in `/var/lib/bind/`
- Cloud-init snippets storage at `/var/lib/vz/snippets`
- Adds `image-builder` Proxmox user with API token for Cluster API

### Kubernetes Architecture (Cluster API)

- Cluster API with CAPMOX provider (`k8s/cluster-api/`)
- `image-builder` Proxmox user/token used by CAPMOX to provision VMs
- Token written to `~/image-builder.token` on the Proxmox host after setup

### AppArmor for BIND9

The shipped `usr.sbin.named` AppArmor profile lacks the `abi/4.0` declaration needed for modern unix socket rules. `proxmox-setup.sh` prepends `abi <abi/4.0>,` to the profile if absent, then deploys `proxmox/dns/apparmor-named-local` to `/etc/apparmor.d/local/usr.sbin.named` granting named access to `/run/systemd/notify` (for sd_notify) and `/proc/version_signature`. `apparmor_parser -r` reloads the profile. Note: `network unix` rules do not work on this Proxmox kernel — unix socket permissions must use `unix (create) type=...` syntax, which requires the `abi/4.0` header.

## Important Implementation Details

- `init-proxmox.sh` runs `dos2unix` on all files before copying to Proxmox to normalize Windows line endings
- All scripts use `set -euo pipefail` for error handling
- SSH keys deployed from `~/.ssh/id_ed25519.pub` (john) and `~/.ssh/ansible.pub` (auto-created if missing)
- VMs use VirtIO SCSI controllers with SSD emulation and discard support
- VM IDs match the last octet of their IP address for easy identification