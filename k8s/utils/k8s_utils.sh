#!/usr/bin/env bash

function get_k8s_version() {
  if [ -z "${K8S_VERSION:-}" ]; then
    K8S_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt | sed 's/^v//')
    echo "${K8S_VERSION}"
  else
    # Allow callers to pass v1.36.2 or 1.36.2
    echo "${K8S_VERSION#v}"
  fi
}

function get_k8s_series() {
  local version=${1#v}
  echo "${version}" | cut -d. -f1-2
}

# Resolve the pkgs.k8s.io deb package version for kubelet (e.g. 1.36.2-2.1).
# Stable release tags and apt package revision suffixes are not always "-1.1"
# (1.36.2 published as 1.36.2-2.1). Hardcoding "-1.1" causes Packer/Ansible to
# fail with: no available installation candidate for kubelet=X.Y.Z-1.1
function get_k8s_deb_version() {
  local version=${1#v}
  local series
  series=$(get_k8s_series "${version}")
  local packages_url="https://pkgs.k8s.io/core:/stable:/v${series}/deb/Packages"
  local deb_version
  deb_version=$(
    curl -fsSL "${packages_url}" | awk -v ver="${version}" '
      $1 == "Package:" && $2 == "kubelet" { want = 1; next }
      want && $1 == "Version:" {
        if ($2 ~ ("^" ver "-")) print $2
        want = 0
      }
    ' | sort -V | tail -n1
  )
  if [ -z "${deb_version}" ]; then
    echo "ERROR: no kubelet package matching ${version}-* at ${packages_url}" >&2
    return 1
  fi
  echo "${deb_version}"
}

function get_capi_node_vm_id() {
  local version="${1:-${K8S_VERSION:-}}"
  # Strip leading 'v' and dots, then prepend '10'
  # e.g. v1.35.3 -> 101353
  local digits
  digits=$(echo "${version}" | sed 's/^v//; s/\.//g')
  echo "10${digits}"
}

function get_capi_version() {
  if [ -z "${CAPI_VERSION:-}" ]; then
    CAPI_VERSION=$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/cluster-api/releases/latest | jq -r '.tag_name')
    echo "${CAPI_VERSION}"
  else
    echo "${CAPI_VERSION}"
  fi
}