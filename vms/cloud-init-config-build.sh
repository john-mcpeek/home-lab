#!/usr/bin/env bash
set -euo pipefail

./base/generate-cloud-init-files.sh
./k8s/generate-cloud-init-files.sh
./postgres/generate-cloud-init-files.sh

#scp \
#  base/build-base-templates.sh \
#  k8s/build-k8s-vms.sh \
#  postgres/build-postgres-vm.sh \
#  generated/user-data-*.mime root@pve.lab:~/
#ssh root@pve.lab 'cp *.mime /var/lib/vz/snippets/'