# Proxmox Home Lab Automation

## Proxmox Installation

There are two ways to install Proxmox VE:

### Option A: Manual Installation

- Install Proxmox VE 9.x Terminal UI
- Agree to license terms
- Target disk — `next`
- Region
    - Country: `United States`
    - Timezone: `America/New_York`
    - Keyboard: `US English`
- Admin
    - Password: `password123`
    - Confirm: `password123`
    - Email: `admin@pve.lab`
- Management Interface
    - Hostname: `pve.lab`
    - IP: `10.0.0.10`/`24`
    - Gateway: `10.0.0.1`
    - DNS: `1.1.1.1`
- Install — `next`
- When install completes, remove the USB drive. It will auto-reboot.

### Option B: Automated Installation (USB)

Use `proxmox/auto-install/` to build a custom ISO that installs Proxmox unattended:

```bash
cd proxmox/auto-install
# Edit answer.toml with your desired settings, then:
./create-proxmox-auto-iso.sh
# Flash the resulting ISO to a USB drive and boot the target machine from it.
```

The script downloads the latest Proxmox VE ISO, injects `answer.toml`, writes the result to a detected USB drive, and
ejects it when done.

---

**Note:** If you have connected to `pve.lab` or `10.0.0.10` before, remove the old SSH entry first:

```bash
ssh-keygen -R "10.0.0.10"
```

## Prerequisites

- **Proxmox VE 9.x**
- Network: 10.0.0.0/24 subnet with `vmbr0` bridge
- Storage: `local` configured (`lvm.maxvz = 0`)
- Ed25519 SSH key at `~/.ssh/id_ed25519`
- Ansible SSH key auto-generated if missing
- `./root-password` file containing the Proxmox root password
- `./postgres-password` file containing the desired PostgreSQL password

## Quick Start

Create the password files, then run the main init script:

```bash
echo "yourRootPassword" > ./root-password
echo "yourPostgresPassword" > ./postgres-password
./init-proxmox.sh 10.0.0.10
```

1. You will be prompted to accept the Proxmox host as a known SSH host.
2. The script reads both passwords from their respective files — no interactive prompts after that.

## What Gets Created

### Proxmox Host Configuration

- Subscription repos disabled; no-subscription repos enabled
- Packages installed: `bind9`, `jq`, `vim`, `snapd`, `cloud-init`, `apparmor-utils`
- SSH keys copied to Proxmox host
- Resource pools created: `infra`, `dev`, `uat`, `prod`, `templates`
- `image-builder@pve` user with `capi` API token (token saved to `~/image-builder.token` on Proxmox)
- Tag style configured (ordered, full-shape)
- `/var/lib/vz/snippets` directory created for cloud-init snippets

### DNS Server

- BIND9 configured as authoritative for the `.lab` domain
- Dynamic DNS (DDNS) with TSIG key at `/etc/bind/keys/ddns.key`
- Static zone files in `/etc/bind/`; journal/writable files in `/var/lib/bind/`
- AppArmor profile patched with `abi/4.0` header for unix socket rules
- Proxmox host resolves as `pve.lab` / `10.0.0.10`

### Base VM Template (VM ID 9999)

- Ubuntu 24.04 cloud image, 10GB disk, DHCP
- QEMU guest agent, SSH keys for `john` and `ansible` users
- Auto-registers hostname with DNS on boot via DDNS
- **Auto-shuts down after first boot** so `qm template` can convert it unattended.
  Clone it and use a cloud-init "topper" to override the shutdown (see `blank` VM example).

### VMs

| VM                  | ID    | Pool      | Cores | RAM   | Disk   | IP              |
|---------------------|-------|-----------|-------|-------|--------|-----------------|
| Base template       | 9999  | templates | 2     | 2 GB  | 10 GB  | DHCP            |
| Blank (example)     | 777   | dev       | 1     | 1 GB  | 10 GB  | DHCP            |
| PostgreSQL          | 100   | dev       | 4     | 16 GB | 100 GB | 10.0.0.100/24   |
| Cluster API Manager | 10000 | infra     | 2     | 2 GB  | 20 GB  | DHCP (auto-DNS) |

#### Blank VM (ID 777)

- Minimal example showing how to clone the base template with a cloud-init topper
- Topper cancels the auto-shutdown so the VM stays running

#### PostgreSQL (ID 100)

- PostgreSQL 18 + pgvector
- `scram-sha-256` authentication, listens on all interfaces (10.0.0.0/8 allowed)
- `shared_buffers` tuned to 1 GB

#### Cluster API Manager (ID 10000)

- Bootstrap host for Cluster API + CAPMOX
- Runs `kind` cluster with Cluster API controllers
- Uses `image-builder@pve` token to provision Kubernetes node VMs on Proxmox
- CAPI node VM IDs are derived from the Kubernetes version (e.g. `v1.35.3` → VM ID `101353`)

## Architecture

### Network

| Setting        | Value                    |
|----------------|--------------------------|
| Subnet         | 10.0.0.0/24              |
| Gateway        | 10.0.0.1                 |
| Bridge         | vmbr0                    |
| DNS (primary)  | Proxmox host (10.0.0.10) |
| DNS (fallback) | 8.8.8.8                  |

### Directory Structure

```
.
├── init-proxmox.sh                  # Main entry point — runs all init-*.sh scripts
├── root-password                    # Proxmox root password (gitignored)
├── postgres-password                # PostgreSQL password (gitignored)
├── Reset-DNS.ps1                    # Windows: reset DNS to DHCP
├── Set-StaticIPandDNS.ps1           # Windows: set static IP and point DNS at lab
├── proxmox/
│   ├── proxmox-setup.sh             # Runs on Proxmox: repos, packages, BIND9, pools, users
│   ├── auto-install/
│   │   ├── answer.toml              # Unattended install config (root hash filled in by init-proxmox.sh)
│   │   └── create-proxmox-auto-iso.sh  # Builds a bootable auto-install USB ISO
│   └── dns/
│       ├── named.conf.local         # BIND9 zone declarations + DDNS policy
│       ├── named.conf.options       # BIND9 options (forwarders, recursion)
│       ├── db.lab                   # Forward zone template for .lab
│       ├── db.10.0.0                # Reverse zone template for 10.0.0.x
│       ├── resolv.conf              # resolv.conf template (points to Proxmox)
│       └── apparmor-named-local     # AppArmor local override for named
├── k8s/
│   └── cluster-api/
│       ├── k8s_utils.sh             # Shared functions: k8s version, CAPI version, VM ID derivation
│       ├── clusterctl.yaml          # clusterctl config for CAPMOX
│       ├── kind-cluster-with-extramounts.yaml
│       └── proxmox-env.sh           # CAPMOX environment variables
└── vms/
    ├── init-base.sh                 # Creates base template (VM 9999)
    ├── init-blank.sh                # Creates blank example VM (VM 777)
    ├── init-postgres.sh             # Creates PostgreSQL VM (VM 100)
    ├── init-capi-manager.sh         # Creates Cluster API Manager VM (VM 10000)
    ├── base/                        # Base template cloud-init files
    ├── blank/                       # Blank VM cloud-init files
    ├── postgres/                    # PostgreSQL VM cloud-init files
    └── cluster-api-manager/         # Cluster API Manager cloud-init files
```

## Individual Component Setup

```bash
cd vms

# Base template only
./init-base.sh $PROXMOX_IP

# Blank VM only
./init-blank.sh $PROXMOX_IP

# PostgreSQL VM (reads password from ../postgres-password)
./init-postgres.sh $PROXMOX_IP $POSTGRES_PASSWORD

# Cluster API Manager
./init-capi-manager.sh $PROXMOX_IP
```

## VM Creation Pattern

All VMs clone from the base template (VM ID 9999):

```bash
# Clone template
qm clone 9999 <VM_ID> --name <VM_NAME> --pool <POOL>

# Configure resources
qm set <VM_ID> --cores <CORES>
qm set <VM_ID> --memory <MEMORY_MB>

# Resize disk (optional)
qm resize <VM_ID> scsi0 <SIZE>G

# Attach cloud-init topper
qm set <VM_ID> --cicustom "user=local:snippets/<your-cloud-init>.mime"

# Configure networking
qm set <VM_ID> --ipconfig0 "ip=10.0.0.<LAST_OCTET>/24,gw=10.0.0.1"
qm set <VM_ID> --nameserver "<DNS_IP> 8.8.8.8"

# Add tags and start
qm set <VM_ID> --tags "tag1 tag2"
qm start <VM_ID>
```

VM IDs match the last octet of their static IP for easy identification.

## Windows Host Setup

Two PowerShell scripts configure the Windows host to use the lab's DNS:

```powershell
# Point the active NIC at the lab DNS server
.\Set-StaticIPandDNS.ps1

# Revert — reset the NIC back to DHCP
.\Reset-DNS.ps1
```

## DNS Testing

```bash
# Forward lookup
dig @10.0.0.10 pve.lab

# Reverse lookup
dig @10.0.0.10 -x 10.0.0.10

# From Proxmox host itself
dig @localhost pve.lab
named-checkzone lab /var/lib/bind/db.lab
named-checkzone 0.0.10.in-addr.arpa /var/lib/bind/db.10.0.0
```

## SSH Access

```bash
ssh john@<VM_IP>
ssh -i ~/.ssh/ansible ansible@<VM_IP>
```

## Troubleshooting

### BIND9 Not Starting

```bash
systemctl status named
journalctl -u named --no-pager | tail -30
apparmor_parser -r /etc/apparmor.d/usr.sbin.named
```

### Base Template Auto-Shutdown

Expected behavior — the template shuts down after first boot so `qm template` can convert it unattended. Clone the
template and include a cloud-init topper that overrides the shutdown (see `vms/blank/`).

### Cloud-init Not Applying

```bash
# Verify snippet is present
ls -la /var/lib/vz/snippets/

# Check VM config
qm config <VM_ID>

# Force regenerate
qm cloudinit update <VM_ID>
```

### DDNS Key Rotation

The TSIG key at `/etc/bind/keys/ddns.key` is generated once and never rotated by `proxmox-setup.sh` (re-running skips
generation if the file exists). Rotating the key invalidates the secret baked into existing VM templates — rebuild
templates after a rotation.
