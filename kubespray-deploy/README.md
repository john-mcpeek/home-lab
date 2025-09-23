# Kubespray Deployment

Deploy Kubernetes to the home lab VMs using the official Kubespray container.

## Prerequisites

1. VMs must be created first:
   ```bash
   ./init-proxmox.sh $PROXMOX_IP $PROXMOX_PASSWORD $POSTGRES_PASSWORD
   ```

2. Ensure ansible SSH key exists:
   ```bash
   ls ~/.ssh/ansible  # Should exist
   ```

## Setup

Initialize Kubespray deployment (clones repo and pulls container):
```bash
    cd kubespray-deploy
    ./init-kubespray-deploy.sh
```

## Deploy Kubernetes

Deploy a new cluster:
```bash
   ./deploy-k8s.sh
```

## Cluster Operations

### Scale cluster (add/remove nodes)
First update `inventory/lab/host.yaml`, then:
```bash
   ./scale-cluster.sh
```

### Upgrade Kubernetes version
```bash
   ./upgrade-cluster.sh
```

### Reset cluster (remove Kubernetes)
```bash
./reset-cluster.sh
```

## Advanced Usage

### Custom playbook
```bash
   ./deploy-k8s.sh playbooks/custom.yml
```

### Pass extra vars
```bash
   ./deploy-k8s.sh cluster.yml -e "kube_version=v1.29.0"
```

### Dry run
```bash
   ./deploy-k8s.sh cluster.yml --check
```

## Troubleshooting

### SSH issues
Ensure ansible user can SSH to all nodes:
```bash
   ssh -i ~/.ssh/ansible ansible@10.0.0.141 hostname
```

### Container version
To use a different Kubespray version:
```bash
   KUBESPRAY_VERSION=v2.27.0 ./deploy-k8s.sh
```