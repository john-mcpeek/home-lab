#!/usr/bin/env bash

function get_k8s_version() {
  if [ -z "${K8S_VERSION:-}" ]; then
    K8S_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt | sed 's/^v//')
    echo "${K8S_VERSION}"
  else
    echo "${K8S_VERSION}"
  fi
}

function get_k8s_series() {
  K8S_VERSION=$1
  K8S_SERIES=$(echo "${K8S_VERSION}" | cut -d. -f1-2)
  echo "${K8S_SERIES}"
}

function get_capi_version() {
  if [ -z "${CAPI_VERSION:-}" ]; then
    CAPI_VERSION=$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/cluster-api/releases/latest | jq -r '.tag_name')
    echo "${CAPI_VERSION}"
  else
    echo "${CAPI_VERSION}"
  fi
}