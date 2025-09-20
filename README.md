# Usage

```bash
    ./init-proxmox.sh $PROXMOX_HOST $PROXMOX_ROOT_PASSWORD
```

It takes a few minutes to complete. What it gives you:

- Proxmox subscription sources are disabled
- Proxmox non-subscription repositories are enabled
- ssh keys are copied
- Dynamic DNS is configured
    - Proxmox is the DNS provider
    - Base images for both static and dynamic IPs are created
- Base images
    - setup with qemu-guest-agent
    - ssh keys for john and proxmox root user are installed

test2