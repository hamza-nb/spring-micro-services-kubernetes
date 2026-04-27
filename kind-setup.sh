#!/usr/bin/env bash
# kind-setup.sh — Create a Kind cluster with multiple workers + MetalLB load balancer
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

CLUSTER_NAME="ecommerce"
METALLB_VERSION="v0.14.9"

# ─── Prerequisites check ──────────────────────────────────────────────────────
for cmd in kind kubectl docker; do
  command -v "$cmd" &>/dev/null || error "'$cmd' is not installed or not in PATH"
done

# ─── Step 1: Create Kind cluster ──────────────────────────────────────────────
info "Creating Kind cluster '$CLUSTER_NAME' (1 control-plane + 2 workers)..."

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  warn "Cluster '$CLUSTER_NAME' already exists — skipping creation"
else
  kind create cluster --config "$ROOT/kind-config.yaml"
  success "Cluster created"
fi

kubectl config use-context "kind-${CLUSTER_NAME}"

# ─── Step 2: Load Docker images into Kind ─────────────────────────────────────
info "Loading Docker images into Kind nodes..."

IMAGES="config-server discovery-server customer-service gateway-service notification-service order-service payment-service product-service"

for image in $IMAGES; do
  if docker image inspect "$image" &>/dev/null; then
    info "  Loading $image ..."
    kind load docker-image "$image" --name "$CLUSTER_NAME"
    success "  Loaded $image"
  else
    warn "  Image '$image' not found locally — skipping (build it first with ./deploy.sh --build-only)"
  fi
done

# ─── Step 3: Install MetalLB ──────────────────────────────────────────────────
info "Installing MetalLB ${METALLB_VERSION}..."

kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"

info "Waiting for MetalLB controller to be ready..."
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=120s

success "MetalLB is ready"

# ─── Step 4: Configure MetalLB IP pool from Kind's Docker network ─────────────
info "Detecting Kind Docker network subnet..."

# Kind uses a Docker bridge network named 'kind'
NETWORK_SUBNET="$(docker network inspect kind \
  --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null \
  | head -n1)"

[ -z "$NETWORK_SUBNET" ] && error "Could not detect Kind Docker network subnet"
info "  Subnet: $NETWORK_SUBNET"

# Derive a safe IP range from the last /8 block of the subnet
# e.g. 172.18.0.0/16  →  172.18.255.200 - 172.18.255.250
BASE="$(echo "$NETWORK_SUBNET" | cut -d'.' -f1-2)"
IP_RANGE_START="${BASE}.255.200"
IP_RANGE_END="${BASE}.255.250"

info "  MetalLB pool: ${IP_RANGE_START} - ${IP_RANGE_END}"

kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: kind-pool
  namespace: metallb-system
spec:
  addresses:
    - ${IP_RANGE_START}-${IP_RANGE_END}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: kind-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - kind-pool
EOF

success "MetalLB IP pool configured (${IP_RANGE_START} - ${IP_RANGE_END})"

# ─── Step 5: Summary ──────────────────────────────────────────────────────────
echo ""
info "════════════════════════════════════════════════════════"
info " Kind cluster '${CLUSTER_NAME}' is ready"
info ""
info " Nodes:"
kubectl get nodes -o wide
echo ""
info " Next: run ./deploy.sh to deploy the platform"
info "  The gateway LoadBalancer will get an IP from the pool above"
info "  Check it with: kubectl get svc -n e-commerce gateway-service-svc"
info "════════════════════════════════════════════════════════"
