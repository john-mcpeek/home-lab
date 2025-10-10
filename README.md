# Usage

## Initial Setup

```bash
    ssh-keygen -t ed25519 -C ansible@home.lab
    ./init-proxmox.sh $PROXMOX_HOST_IP $PROXMOX_ROOT_PASSWORD $POSTGRES_PASSWORD
```

It takes a few minutes to complete. What it gives you:

- Proxmox subscription sources are disabled
- Proxmox non-subscription repositories are enabled
- ssh keys are copied
- Dynamic DNS is configured
    - Proxmox is the DNS provider
    - Base image created with auto register DNS configured and changed to a template

- Base image
    - setup with qemu-guest-agent
    - ssh keys for john and ansible user are installed
    - <b>Note:</b> The base image will always shut down. This is expected. This enables
      building without user intervention. However, it means you need to use a cloud-init script
      to configure the final VM. As for example, you can see in the `blank` VM.
- Blank VM
  - Nothing special, but mostly empty cloud-init script. This is an example of how to use the base image.
- Postgres
  - Simple Postgres server.
- Kubespray VMs
  - VMs ready to use as Kubernetes nodes managed by kubespray.
  - Ansible inventory is used to configure the VMs for nodes.

## Deploy Kubernetes Cluster

After VMs are created, deploy an HA Kubernetes cluster using the official Kubespray container:

```bash
    cd kubespray-deploy
    ./init-kubespray-deploy.sh  # One-time setup: clones Kubespray and pulls container
    ./deploy-k8s.sh             # Deploy Kubernetes to the VMs
```

The deployment uses:
- Official Kubespray container image (`quay.io/kubespray/kubespray:v2.28.1`)
- Pre-configured inventory at `inventory/lab/host.yaml`
- 3 control plane nodes (10.0.0.141-143) and 4 worker nodes (10.0.0.151-154)

Additional operations:
- `./scale-cluster.sh` - Add or remove nodes
- `./upgrade-cluster.sh` - Upgrade Kubernetes version
- `./reset-cluster.sh` - Remove Kubernetes from all nodes