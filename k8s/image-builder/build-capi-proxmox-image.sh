#!/usr/bin/env bash
set -euo pipefail

docker build . -t image-builder-with-pve-crt

export ISO_IMAGE=ubuntu-24.04.3-live-server-amd64.iso

docker run -it --rm --net=host --env-file proxmox.env \
  -v ./proxmox_packer_overrides.json:/home/imagebuilder/proxmox_packer_overrides.json \
  -v /home/john/kubernetes:/home/imagebuilder/images/capi/downloaded_iso_path \
  image-builder-with-pve-crt build-proxmox-ubuntu-2404-efi