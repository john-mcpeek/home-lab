#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# init-capi-cluster.sh
# Bootstraps a Kubernetes workload cluster on Proxmox using Cluster API (CAPI)
# with a temporary Kind management cluster.
#
# Run this script on the cluster-api-manager VM:
#   ssh john@cluster-api-manager.lab
#   cd ~/home-lab/k8s/cluster-capi && ./init-capi-cluster.sh
# =============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# =============================================================================
# Configurable variables — override any of these with env vars before running
# =============================================================================

CLUSTER_NAME="${CLUSTER_NAME:-capi-cluster}"
CONTROL_PLANE_COUNT="${CONTROL_PLANE_COUNT:-1}"
WORKER_COUNT="${WORKER_COUNT:-3}"
BOOTSTRAP_CLUSTER_NAME="${BOOTSTRAP_CLUSTER_NAME:-capi-bootstrap}"
KUBECONFIG_OUT="${KUBECONFIG_OUT:-${HOME}/.kube/${CLUSTER_NAME}.kubeconfig}"

# Proxmox connection (PROXMOX_SECRET must come from env or ~/image-builder.token)
PROXMOX_URL="${PROXMOX_URL:-https://pve.lab:8006}"
PROXMOX_TOKEN="${PROXMOX_TOKEN:-image-builder@pve!capi}"

# Proxmox cluster topology
PROXMOX_SOURCENODE="${PROXMOX_SOURCENODE:-pve}"
ALLOWED_NODES="${ALLOWED_NODES:-[pve]}"
VM_SSH_KEYS="${VM_SSH_KEYS:-id_ed25519}"

# Network — matches clusterctl.yaml and the 10.0.0.0/24 lab network
CONTROL_PLANE_ENDPOINT_IP="${CONTROL_PLANE_ENDPOINT_IP:-10.0.0.39}"
NODE_IP_RANGES="${NODE_IP_RANGES:-[10.0.0.40-10.0.0.50]}"
GATEWAY="${GATEWAY:-10.0.0.1}"
IP_PREFIX="${IP_PREFIX:-24}"
DNS_SERVERS="${DNS_SERVERS:-[10.0.0.10,8.8.4.4]}"
BRIDGE="${BRIDGE:-vmbr0}"

# Workload VM specs
NUM_SOCKETS="${NUM_SOCKETS:-1}"
NUM_CORES="${NUM_CORES:-4}"
MEMORY_MIB="${MEMORY_MIB:-8192}"
BOOT_VOLUME_DEVICE="${BOOT_VOLUME_DEVICE:-scsi0}"
BOOT_VOLUME_SIZE="${BOOT_VOLUME_SIZE:-40}"

# Feature gates required by CAPMOX
EXP_CLUSTER_RESOURCE_SET="${EXP_CLUSTER_RESOURCE_SET:-true}"
CLUSTER_TOPOLOGY="${CLUSTER_TOPOLOGY:-true}"

# =============================================================================
# Helper functions
# =============================================================================

log_section() {
  echo ""
  echo "============================================================"
  echo "  $*"
  echo "============================================================"
}

# wait_for_condition DESCRIPTION TIMEOUT INTERVAL COMMAND [ARGS...]
# Polls COMMAND until it exits 0, or until TIMEOUT seconds have elapsed.
wait_for_condition() {
  local description="$1"
  local timeout="$2"
  local interval="$3"
  shift 3
  local start elapsed
  start=$(date +%s)
  while true; do
    if "$@" 2>/dev/null; then
      echo "  Ready: ${description}"
      return 0
    fi
    elapsed=$(( $(date +%s) - start ))
    if (( elapsed >= timeout )); then
      echo "ERROR: Timed out waiting for: ${description} (${timeout}s elapsed)" >&2
      return 1
    fi
    echo "  Waiting for ${description}... (${elapsed}/${timeout}s)"
    sleep "${interval}"
  done
}

check_prereqs() {
  local missing=()
  for tool in kind kubectl clusterctl helm docker jq; do
    if ! command -v "${tool}" &>/dev/null; then
      missing+=("${tool}")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    echo "ERROR: Missing required tools: ${missing[*]}" >&2
    echo "These are pre-installed on the cluster-api-manager VM via cloud-init." >&2
    exit 1
  fi
}

load_proxmox_secret() {
  if [ -n "${PROXMOX_SECRET:-}" ]; then
    echo "  Using PROXMOX_SECRET from environment."
    return 0
  fi

  local token_file="${HOME}/image-builder.token"
  if [ -f "${token_file}" ]; then
    echo "  Reading PROXMOX_SECRET from ${token_file}"
    PROXMOX_SECRET=$(grep PROXMOX_SECRET "${token_file}" | cut -d'=' -f2- | sed -e 's/\"//g')
    export PROXMOX_SECRET
    if [ -z "${PROXMOX_SECRET}" ]; then
      echo "ERROR: PROXMOX_SECRET key found in ${token_file} but value is empty." >&2
      exit 1
    fi
    return 0
  fi

  echo "ERROR: PROXMOX_SECRET is not set and ${token_file} does not exist." >&2
  echo "Either:" >&2
  echo "  export PROXMOX_SECRET=<your-token-secret>" >&2
  echo "  or copy ~/image-builder.token from the Proxmox host to this VM." >&2
  exit 1
}

# Wait for a namespace to exist before trying to wait on resources within it
wait_for_namespace() {
  local ns="$1"
  wait_for_condition "namespace/${ns} to exist" 120 5 \
    kubectl get namespace "${ns}" --no-headers
}

# Wait for all deployments in a namespace to be Available
wait_for_deployments() {
  local ns="$1"
  wait_for_namespace "${ns}"
  wait_for_condition "deployments in ${ns} to be Available" 300 10 \
    kubectl wait --for=condition=Available deployment --all -n "${ns}" --timeout=10s
}

# Check all machines for a cluster are in Running phase
all_machines_running() {
  local cluster="$1"
  local total running
  total=$(kubectl get machines -l "cluster.x-k8s.io/cluster-name=${cluster}" \
    --no-headers 2>/dev/null | wc -l)
  running=$(kubectl get machines -l "cluster.x-k8s.io/cluster-name=${cluster}" \
    --no-headers 2>/dev/null | grep -c "Running" || true)
  [[ "${total}" -gt 0 && "${total}" -eq "${running}" ]]
}

# Check all nodes in the workload cluster are Ready
all_nodes_ready() {
  local kubeconfig="$1"
  local total not_ready
  total=$(kubectl --kubeconfig "${kubeconfig}" get nodes --no-headers 2>/dev/null | wc -l)
  not_ready=$(kubectl --kubeconfig "${kubeconfig}" get nodes --no-headers 2>/dev/null \
    | grep -v " Ready" | wc -l || true)
  [[ "${total}" -gt 0 && "${not_ready}" -eq 0 ]]
}

# =============================================================================
# Step 1 — Prerequisite checks
# =============================================================================
log_section "Checking prerequisites"
check_prereqs
echo "  All tools found."

# =============================================================================
# Step 2 — Load Proxmox secret
# =============================================================================
log_section "Loading Proxmox credentials"
load_proxmox_secret

# =============================================================================
# Step 3 — Compute derived values
# =============================================================================
log_section "Computing cluster configuration"

# shellcheck source=../utils/k8s_utils.sh
source "${SCRIPT_DIR}/../utils/k8s_utils.sh"

K8S_VERSION="${K8S_VERSION:-$(get_k8s_version)}"
K8S_VERSION="v${K8S_VERSION#v}"  # ensure leading 'v'

TEMPLATE_VMID=$(get_capi_node_vm_id "${K8S_VERSION}")

echo "  Cluster name:          ${CLUSTER_NAME}"
echo "  Kubernetes version:    ${K8S_VERSION}"
echo "  Template VM ID:        ${TEMPLATE_VMID}"
echo "  Control planes:        ${CONTROL_PLANE_COUNT}"
echo "  Workers:               ${WORKER_COUNT}"
echo "  Bootstrap cluster:     ${BOOTSTRAP_CLUSTER_NAME}"
echo "  Workload kubeconfig:   ${KUBECONFIG_OUT}"

# Export everything clusterctl needs for variable substitution
export PROXMOX_URL PROXMOX_TOKEN PROXMOX_SECRET
export PROXMOX_SOURCENODE ALLOWED_NODES VM_SSH_KEYS
export CONTROL_PLANE_ENDPOINT_IP NODE_IP_RANGES GATEWAY IP_PREFIX DNS_SERVERS BRIDGE
export NUM_SOCKETS NUM_CORES MEMORY_MIB BOOT_VOLUME_DEVICE BOOT_VOLUME_SIZE
export TEMPLATE_VMID KUBERNETES_VERSION="${K8S_VERSION}"
export EXP_CLUSTER_RESOURCE_SET CLUSTER_TOPOLOGY

# =============================================================================
# Step 4 — Create Kind bootstrap cluster
# =============================================================================
log_section "Creating Kind bootstrap cluster: ${BOOTSTRAP_CLUSTER_NAME}"

if kind get clusters 2>/dev/null | grep -q "^${BOOTSTRAP_CLUSTER_NAME}$"; then
  echo "  Kind cluster '${BOOTSTRAP_CLUSTER_NAME}' already exists, skipping creation."
else
  kind create cluster \
    --name "${BOOTSTRAP_CLUSTER_NAME}" \
    --config "${SCRIPT_DIR}/../cluster-api/kind-cluster-with-extramounts.yaml"
fi

kubectl cluster-info --context "kind-${BOOTSTRAP_CLUSTER_NAME}"

# =============================================================================
# Step 5 — Setup clusterctl config
# =============================================================================
log_section "Configuring clusterctl"

mkdir -p "${HOME}/.cluster-api"
cp "${SCRIPT_DIR}/../cluster-api/clusterctl.yaml" "${HOME}/.cluster-api/clusterctl.yaml"
echo "  Copied clusterctl.yaml to ~/.cluster-api/clusterctl.yaml"
echo "  (PROXMOX_SECRET will be substituted from env at runtime — not written to disk)"

# =============================================================================
# Step 6 — Initialize CAPI providers
# =============================================================================
log_section "Initializing CAPI providers (CAPMOX + in-cluster IPAM)"

if kubectl get namespace capi-system --no-headers &>/dev/null; then
  echo "  capi-system namespace already exists, skipping clusterctl init."
else
  clusterctl init --infrastructure proxmox --ipam in-cluster
fi

# =============================================================================
# Step 7 — Wait for providers to be ready
# =============================================================================
log_section "Waiting for CAPI provider deployments to become Available"

wait_for_deployments "capi-system"
wait_for_deployments "capi-kubeadm-bootstrap-system"
wait_for_deployments "capi-kubeadm-control-plane-system"
wait_for_deployments "capmox-system"
wait_for_deployments "capi-ipam-in-cluster-system"

echo "  All providers are Available."

# =============================================================================
# Step 8 — Generate and apply workload cluster manifest
# =============================================================================
log_section "Generating workload cluster manifest"

CLUSTER_MANIFEST="/tmp/${CLUSTER_NAME}-cluster.yaml"

clusterctl generate cluster "${CLUSTER_NAME}" \
  --infrastructure proxmox \
  --kubernetes-version "${K8S_VERSION}" \
  --control-plane-machine-count "${CONTROL_PLANE_COUNT}" \
  --worker-machine-count "${WORKER_COUNT}" \
  > "${CLUSTER_MANIFEST}"

echo "  Manifest written to ${CLUSTER_MANIFEST}"
echo "  Applying manifest..."
kubectl apply -f "${CLUSTER_MANIFEST}"

# =============================================================================
# Step 9 — Wait for workload cluster to be provisioned
# =============================================================================
log_section "Waiting for workload cluster to be provisioned"

echo "  Waiting for cluster phase=Provisioned (up to 600s)..."
wait_for_condition "cluster ${CLUSTER_NAME} to reach Provisioned phase" 600 15 \
  bash -c "[[ \$(kubectl get cluster ${CLUSTER_NAME} -o jsonpath='{.status.phase}' 2>/dev/null) == 'Provisioned' ]]"

echo "  Waiting for all machines to reach Running phase (up to 900s)..."
wait_for_condition "all machines in ${CLUSTER_NAME} to be Running" 900 20 \
  all_machines_running "${CLUSTER_NAME}"

echo "  Cluster provisioned. Machine status:"
kubectl get machines -l "cluster.x-k8s.io/cluster-name=${CLUSTER_NAME}"

# =============================================================================
# Step 10 — Retrieve workload cluster kubeconfig
# =============================================================================
log_section "Retrieving workload cluster kubeconfig"

mkdir -p "$(dirname "${KUBECONFIG_OUT}")"
clusterctl get kubeconfig "${CLUSTER_NAME}" > "${KUBECONFIG_OUT}"
chmod 600 "${KUBECONFIG_OUT}"
echo "  Kubeconfig written to: ${KUBECONFIG_OUT}"
kubectl --kubeconfig "${KUBECONFIG_OUT}" cluster-info

# =============================================================================
# Step 11 — Install Calico CNI on workload cluster
# =============================================================================
log_section "Installing Calico CNI on workload cluster"

helm repo add projectcalico https://docs.tigera.io/calico/charts 2>/dev/null || true
helm repo update projectcalico

if helm status calico -n tigera-operator --kubeconfig "${KUBECONFIG_OUT}" &>/dev/null; then
  echo "  Calico already installed, skipping."
else
  helm upgrade --install calico projectcalico/tigera-operator \
    --namespace tigera-operator \
    --create-namespace \
    --kubeconfig "${KUBECONFIG_OUT}" \
    --wait \
    --timeout 5m
fi

# =============================================================================
# Step 12 — Wait for workload nodes to be Ready
# =============================================================================
log_section "Waiting for workload cluster nodes to be Ready"

wait_for_condition "all nodes in ${CLUSTER_NAME} to be Ready" 600 20 \
  all_nodes_ready "${KUBECONFIG_OUT}"

echo "  Node status:"
kubectl --kubeconfig "${KUBECONFIG_OUT}" get nodes

# =============================================================================
# Summary
# =============================================================================
log_section "Cluster ready"

echo "  Cluster:     ${CLUSTER_NAME}"
echo "  Kubeconfig:  ${KUBECONFIG_OUT}"
echo ""
echo "  Access the cluster:"
echo "    export KUBECONFIG=${KUBECONFIG_OUT}"
echo "    kubectl get nodes"
echo "    kubectl get pods -A"
echo ""
echo "  Check CAPI objects (from bootstrap cluster):"
echo "    clusterctl describe cluster ${CLUSTER_NAME}"
echo ""
echo "  Tear down workload cluster:"
echo "    kubectl delete cluster ${CLUSTER_NAME}"
echo ""
echo "  Tear down bootstrap cluster (after workload cluster is deleted):"
echo "    kind delete cluster --name ${BOOTSTRAP_CLUSTER_NAME}"
