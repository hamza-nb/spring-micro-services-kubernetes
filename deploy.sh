#!/usr/bin/env bash
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ─── Map service directory → docker image name ────────────────────────────────
# Usage: image_name <dir>
image_name() {
  case "$1" in
    config-server) echo "config-server"    ;;
    discovery)     echo "discovery-server" ;;
    customer)      echo "customer-service" ;;
    gateway)       echo "gateway-service"  ;;
    notification)  echo "notification-service" ;;
    order)         echo "order-service"    ;;
    payment)       echo "payment-service"  ;;
    product)       echo "product-service"  ;;
    *) error "Unknown service: $1" ;;
  esac
}

SERVICES="config-server discovery customer gateway notification order payment product"

# ─── Flags ────────────────────────────────────────────────────────────────────
BUILD=true
DEPLOY=true
SERVICE_FILTER=""

usage() {
  echo "Usage: $0 [options]"
  echo "  --build-only       Only build Docker images, skip K8s deploy"
  echo "  --deploy-only      Only apply K8s manifests, skip Docker build"
  echo "  --service <name>   Build/deploy a single service (e.g. customer)"
  echo "  --help             Show this help"
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --build-only)  DEPLOY=false; shift ;;
    --deploy-only) BUILD=false;  shift ;;
    --service)     SERVICE_FILTER="$2"; shift 2 ;;
    --help)        usage ;;
    *) error "Unknown option: $1" ;;
  esac
done

# ─── Step 1: Build Docker images ──────────────────────────────────────────────
if $BUILD; then
  echo ""
  info "════════════════════════════════════════"
  info " Building Docker images"
  info "════════════════════════════════════════"

  for dir in $SERVICES; do
    [ -n "$SERVICE_FILTER" ] && [ "$dir" != "$SERVICE_FILTER" ] && continue

    image="$(image_name "$dir")"
    svc_path="$ROOT/services/$dir"

    [ ! -d "$svc_path" ]       && error "Service directory not found: $svc_path"
    [ ! -f "$svc_path/Dockerfile" ] && error "Dockerfile missing in $svc_path"

    info "Building image '$image' from services/$dir ..."
    docker build -t "$image" "$svc_path" || error "Docker build failed for $image"
    success "Built $image"
  done
fi

# ─── Step 2: Apply Kubernetes manifests ───────────────────────────────────────
if $DEPLOY; then
  echo ""
  info "════════════════════════════════════════"
  info " Deploying to Kubernetes"
  info "════════════════════════════════════════"

  # 2a. Namespace first
  info "Applying namespace..."
  kubectl apply -f "$ROOT/k8-namespace.yaml"

  if [ -z "$SERVICE_FILTER" ]; then
    # 2b. Infrastructure
    info "Applying infrastructure (postgres, kafka, zipkin, mailer, kafka-ui)..."
    kubectl apply \
      -f "$ROOT/k8-postgres.yaml" \
      -f "$ROOT/k8-kafka.yaml" \
      -f "$ROOT/k8-zipkin.yaml" \
      -f "$ROOT/k8-mailer-dev.yaml" \
      -f "$ROOT/k8-kafka-ui.yaml"

    # 2c. Config server (ConfigMaps before Deployment)
    info "Applying config-server..."
    kubectl apply \
      -f "$ROOT/services/config-server/k8-configmap-config-server-root-configuration.yaml" \
      -f "$ROOT/services/config-server/k8-configmap-config-server-configurations.yaml" \
      -f "$ROOT/services/config-server/k8-config-service.yaml"

    info "Waiting for config-server to be ready..."
    kubectl rollout status deployment/config-service-dep \
      -n e-commerce --timeout=120s \
      || warn "config-server not ready yet, continuing anyway"

    # 2d. Discovery service
    info "Applying discovery-service..."
    kubectl apply -f "$ROOT/services/discovery/k8-discovery-service.yaml"

    info "Waiting for discovery-service to be ready..."
    kubectl rollout status deployment/discovery-service-dep \
      -n e-commerce --timeout=120s \
      || warn "discovery-service not ready yet, continuing anyway"

    # 2e. Business microservices
    info "Applying microservices..."
    kubectl apply \
      -f "$ROOT/services/customer/k8-customer-service.yaml" \
      -f "$ROOT/services/gateway/k8-gateway-service.yaml" \
      -f "$ROOT/services/notification/k8-notification-service.yaml" \
      -f "$ROOT/services/order/k8-order-service.yaml" \
      -f "$ROOT/services/payment/k8-payment-service.yaml" \
      -f "$ROOT/services/product/k8-product-service.yaml"

  else
    # Single-service deploy
    if [ "$SERVICE_FILTER" = "config-server" ]; then
      kubectl apply \
        -f "$ROOT/services/config-server/k8-configmap-config-server-root-configuration.yaml" \
        -f "$ROOT/services/config-server/k8-configmap-config-server-configurations.yaml" \
        -f "$ROOT/services/config-server/k8-config-service.yaml"
    else
      svc_yaml="$ROOT/services/$SERVICE_FILTER/k8-${SERVICE_FILTER}-service.yaml"
      [ ! -f "$svc_yaml" ] && error "K8s manifest not found: $svc_yaml"
      kubectl apply -f "$svc_yaml"
    fi
  fi

  # ─── Summary ────────────────────────────────────────────────────────────────
  echo ""
  info "════════════════════════════════════════"
  info " Deployment complete — pod status:"
  info "════════════════════════════════════════"
  kubectl get pods -n e-commerce
fi
