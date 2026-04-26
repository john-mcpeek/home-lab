# Cluster API on Proxmox — Bootstrap Guide

This directory contains the script that creates a Kubernetes workload cluster running on Proxmox VMs, managed by [Cluster API (CAPI)](https://cluster-api.sigs.k8s.io/). A temporary [Kind](https://kind.sigs.k8s.io/) cluster running on the `cluster-api-manager` VM acts as the CAPI management cluster during bootstrapping.

## Overview

```
Local machine
  └─ init-proxmox.sh
       └─ vms/init-capi-manager.sh
            ├─ Provisions cluster-api-manager VM (VM 10000) with Kind, kubectl, clusterctl, Helm
            └─ Builds Proxmox Ubuntu K8s VM template (e.g. VM 101353 for v1.35.3)

cluster-api-manager VM  <-- you are here
  └─ k8s/claude-capi/init-capi-cluster.sh
       ├─ Creates Kind bootstrap cluster (Docker-in-Docker)
       ├─ Installs CAPI + CAPMOX + in-cluster IPAM into Kind
       ├─ Provisions workload cluster VMs in Proxmox
       ├─ Installs Calico CNI
       └─ Returns ~/.kube/capi-cluster.kubeconfig
```

## Prerequisites

Before running `init-capi-cluster.sh`:

1. **Run from the cluster-api-manager VM** — Kind and Docker must be available. All required tools (kind v0.31.0, kubectl, clusterctl, helm) are pre-installed via cloud-init.
   ```bash
   ssh john@cluster-api-manager.lab
   ```

2. **VM template must exist** — The Proxmox Kubernetes VM template (ubuntu-2404-kube-vX.X.X) must already be built. `vms/init-capi-manager.sh` handles this automatically as part of the initial setup.

3. **Proxmox secret available** — The script reads `PROXMOX_SECRET` from `~/image-builder.token` (copy it from the Proxmox host) or from the environment:
   ```bash
   # Option A: copy token file from Proxmox host
   scp root@pve.lab:~/image-builder.token ~/image-builder.token

   # Option B: export directly
   export PROXMOX_SECRET=<your-api-token-secret>
   ```

4. **Repo checked out on the VM:**
   ```bash
   git clone <repo-url> ~/home-lab
   # or
   git -C ~/home-lab pull
   ```

## Quick Start

```bash
ssh john@cluster-api-manager.lab
cd ~/home-lab/k8s/claude-capi
./init-capi-cluster.sh
```

The script takes 10–20 minutes end to end, depending on VM provisioning speed.

When complete:
```bash
export KUBECONFIG=~/.kube/capi-cluster.kubeconfig
kubectl get nodes
kubectl get pods -A
```

## Configuration

All variables can be overridden by exporting them before running the script.

| Variable | Default | Description |
|---|---|---|
| `CLUSTER_NAME` | `capi-cluster` | Name for the workload cluster |
| `K8S_VERSION` | latest stable | Kubernetes version (e.g. `v1.35.3`) |
| `CONTROL_PLANE_COUNT` | `1` | Number of control plane nodes |
| `WORKER_COUNT` | `3` | Number of worker nodes |
| `BOOTSTRAP_CLUSTER_NAME` | `capi-bootstrap` | Name for the Kind bootstrap cluster |
| `KUBECONFIG_OUT` | `~/.kube/capi-cluster.kubeconfig` | Where to write the workload kubeconfig |
| `CONTROL_PLANE_ENDPOINT_IP` | `10.0.0.39` | kube-vip VIP for the control plane |
| `NODE_IP_RANGES` | `[10.0.0.40-10.0.0.50]` | IP pool for workload VMs |
| `NUM_CORES` | `4` | vCPUs per workload VM |
| `MEMORY_MIB` | `8192` | RAM per workload VM (MiB) |
| `BOOT_VOLUME_SIZE` | `40` | Boot disk size per VM (GiB) |
| `PROXMOX_URL` | `https://pve.lab:8006` | Proxmox API endpoint |

Example — smaller cluster with a specific K8s version:
```bash
CLUSTER_NAME=dev-cluster K8S_VERSION=v1.35.3 WORKER_COUNT=2 MEMORY_MIB=4096 \
  ./init-capi-cluster.sh
```

## Architecture Decisions

### Kind for the bootstrap cluster

Cluster API requires a running Kubernetes cluster to host the CAPI controllers. This creates a chicken-and-egg problem: you need k8s to create k8s. Kind (Kubernetes in Docker) solves this by running a fully functional cluster inside Docker containers — no VMs, no pre-existing infrastructure required.

The `cluster-api-manager` VM is purpose-built for this: it has Docker installed (so Kind works), and enough RAM to run both Kind and the CAPI controller pods. The Kind cluster is purely ephemeral — it only exists to provision the workload cluster. Once the workload cluster is up, the Kind cluster can be deleted (or left running if you want CAPI to continue managing the workload cluster).

The Kind config used (`k8s/cluster-api/kind-cluster-with-extramounts.yaml`) enables dual-stack IPv4/IPv6 and mounts the Docker socket into the control-plane container. The Docker socket mount is a CAPI convention — some providers need it, and it does no harm here.

### ionos-cloud CAPMOX provider

[ionos-cloud/cluster-api-provider-proxmox](https://github.com/ionos-cloud/cluster-api-provider-proxmox) is the actively maintained Cluster API infrastructure provider for Proxmox VE. It was originally developed under `kubernetes-sigs` and then donated to ionos-cloud where development continues. It:

- Clones VMs from a Proxmox template (the ubuntu-2404-kube image built by `vms/init-capi-manager.sh`)
- Configures networking via cloud-init on each VM
- Integrates with the in-cluster IPAM provider for IP address management
- Uses the `image-builder@pve!capi` API token created during Proxmox setup

The provider credentials (`PROXMOX_URL`, `PROXMOX_TOKEN`, `PROXMOX_SECRET`) are injected as environment variables at `clusterctl init` time. clusterctl substitutes them into `~/.cluster-api/clusterctl.yaml` at runtime — the secret is never written to disk as a literal value.

### in-cluster IPAM provider

The [cluster-api-ipam-provider-in-cluster](https://github.com/kubernetes-sigs/cluster-api-ipam-provider-in-cluster) manages IP address allocation for workload VMs inside Kubernetes itself, using `IPAddressClaim` and `IPAddress` custom resources. This means:

- No external DHCP server needed (the lab's BIND9 handles DNS, not DHCP)
- IP allocation is tracked as Kubernetes objects, visible with `kubectl get ipaddresses`
- The pool is defined by `NODE_IP_RANGES` (10.0.0.40–10.0.0.50 by default), giving 11 addresses for control planes + workers

### Calico CNI

Calico is installed via the Tigera operator Helm chart. Reasons for this choice over alternatives:

- **vs. Flannel**: Calico supports NetworkPolicy, which is needed for any non-trivial workload
- **vs. Cilium**: Cilium requires a newer kernel than what ships with the Proxmox host's Ubuntu base; Calico works on the standard kernel
- **vs. Flannel/Canal**: Calico has native dual-stack support, matching the Kind cluster's dual-stack configuration
- The Tigera operator chart handles CRD installation and upgrades cleanly

### kube-vip for the control plane endpoint

`CONTROL_PLANE_ENDPOINT_IP` (10.0.0.39) is the virtual IP that kube-vip advertises as the stable API server address. CAPMOX injects kube-vip into the cluster bootstrap process automatically when a control plane endpoint IP is set. This gives a single stable endpoint even if you later scale to multiple control plane nodes.

The VIP is reserved outside the `NODE_IP_RANGES` pool (10.0.0.40–10.0.0.50) so IPAM will not accidentally allocate it to a VM.

## Managing the Cluster

### Access the cluster
```bash
export KUBECONFIG=~/.kube/capi-cluster.kubeconfig
kubectl get nodes
kubectl get pods -A
```

### Check CAPI status (from bootstrap cluster, without KUBECONFIG set)
```bash
clusterctl describe cluster capi-cluster
kubectl get clusters,machines,machinedeployments
```

### Scale workers
```bash
# Find the MachineDeployment name
kubectl get machinedeployments

# Scale it
kubectl scale machinedeployment capi-cluster-md-0 --replicas=5
```

### Upgrade Kubernetes
```bash
clusterctl upgrade plan
clusterctl upgrade apply --contract v1beta1
```

## Advanced: Pivoting the Management Cluster

"Pivoting" moves the CAPI management objects from the Kind bootstrap cluster into the workload cluster itself, making the workload cluster self-managing. After a pivot, the Kind cluster can be deleted.

```bash
# 1. Install CAPI providers into the workload cluster
clusterctl init --infrastructure proxmox --ipam in-cluster \
  --kubeconfig "${KUBECONFIG_OUT}"

# 2. Move all CAPI objects from Kind to the workload cluster
clusterctl move \
  --to-kubeconfig "${KUBECONFIG_OUT}"

# 3. Verify objects moved
kubectl --kubeconfig "${KUBECONFIG_OUT}" get clusters,machines

# 4. Delete the bootstrap cluster
kind delete cluster --name capi-bootstrap
```

After pivoting, use the workload cluster's kubeconfig for all `kubectl` and `clusterctl` operations.

## Tearing Down

```bash
# Delete the workload cluster (removes all Proxmox VMs)
kubectl delete cluster capi-cluster

# Wait for VMs to be deleted, then delete the bootstrap cluster
kind delete cluster --name capi-bootstrap
```

Note: `kubectl delete -f /tmp/capi-cluster-cluster.yaml` may leave orphaned IPAM or machine resources. Deleting the cluster object directly (`kubectl delete cluster <name>`) is the recommended approach.

## Relationship to Other Scripts

| Script | Purpose |
|---|---|
| `init-proxmox.sh` | Bootstraps the entire Proxmox host (packages, DNS, pools, image-builder user) |
| `vms/init-capi-manager.sh` | Provisions the cluster-api-manager VM and builds the K8s VM template |
| `k8s/cluster-api/k8s_utils.sh` | Utility functions sourced by this script (`get_k8s_version`, `get_capi_node_vm_id`) |
| `k8s/cluster-api/clusterctl.yaml` | Provider registration and default variable values; copied to `~/.cluster-api/` |
| `k8s/cluster-api/kind-cluster-with-extramounts.yaml` | Kind cluster configuration used for the bootstrap cluster |
