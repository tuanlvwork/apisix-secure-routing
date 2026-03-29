#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — Local cold-start for apisix-secure-routing
# Usage: bash scripts/bootstrap.sh
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INTERNAL_API_KEY="internal-secret-key-CHANGE-IN-PRODUCTION"
START_TS=$SECONDS

# ── ANSI color & style palette ────────────────────────────────────────────────
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"

BLACK="\033[30m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
MAGENTA="\033[35m"
CYAN="\033[36m"
WHITE="\033[37m"

BG_BLUE="\033[44m"
BG_CYAN="\033[46m"

# Semantic aliases
COLOR_STEP="${BOLD}${CYAN}"
COLOR_OK="${BOLD}${GREEN}"
COLOR_WARN="${BOLD}${YELLOW}"
COLOR_ERR="${BOLD}${RED}"
COLOR_DIM="${DIM}${WHITE}"
COLOR_KEY="${BOLD}${MAGENTA}"
COLOR_CMD="${BOLD}${BLUE}"
COLOR_HEAD="${BOLD}${WHITE}"

# ── Helper printers ───────────────────────────────────────────────────────────
banner() {
  echo ""
  echo -e "${BOLD}${BG_BLUE}${WHITE}                                                              ${RESET}"
  echo -e "${BOLD}${BG_BLUE}${WHITE}   ██████╗  █████╗ ████████╗███████╗██╗    ██╗ █████╗ ██╗   ${RESET}"
  echo -e "${BOLD}${BG_BLUE}${WHITE}  ██╔════╝ ██╔══██╗╚══██╔══╝██╔════╝██║    ██║██╔══██╗╚██╗  ${RESET}"
  echo -e "${BOLD}${BG_BLUE}${WHITE}  ██║  ███╗███████║   ██║   █████╗  ██║ █╗ ██║███████║ ██║  ${RESET}"
  echo -e "${BOLD}${BG_BLUE}${WHITE}  ██║   ██║██╔══██║   ██║   ██╔══╝  ██║███╗██║██╔══██║ ██║  ${RESET}"
  echo -e "${BOLD}${BG_BLUE}${WHITE}  ╚██████╔╝██║  ██║   ██║   ███████╗╚███╔███╔╝██║  ██║██╔╝  ${RESET}"
  echo -e "${BOLD}${BG_BLUE}${WHITE}   ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ${RESET}"
  echo -e "${BOLD}${BG_BLUE}${WHITE}                                                              ${RESET}"
  echo -e "${BOLD}${BG_CYAN}${BLACK}      🔒  Secure Routing  ·  APISIX  ·  Kubernetes  ·  NestJS      ${RESET}"
  echo -e "${BOLD}${BG_BLUE}${WHITE}                                                              ${RESET}"
  echo ""
}

divider() {
  echo -e "${COLOR_DIM}  ──────────────────────────────────────────────────────────────${RESET}"
}

step() {
  local num="$1" total="$2" label="$3"
  echo ""
  divider
  echo -e "  ${COLOR_STEP}▶  STEP ${num}/${total}${RESET}  ${BOLD}${label}${RESET}"
  divider
}

info()    { echo -e "     ${COLOR_DIM}→${RESET}  $*"; }
success() { echo -e "     ${COLOR_OK}✔${RESET}  $*"; }
warn()    { echo -e "     ${COLOR_WARN}⚠${RESET}  $*"; }
fail()    { echo -e "     ${COLOR_ERR}✘  ERROR: $*${RESET}" >&2; exit 1; }

elapsed() {
  local s=$(( SECONDS - START_TS ))
  printf "%dm %02ds" $(( s / 60 )) $(( s % 60 ))
}

# ── Prerequisites check ─────────────────────────────────────────────────────
# NOTE: `kubectl apply -k` uses kubectl's BUILT-IN kustomize engine.
#       Standalone `kustomize` CLI is NOT required.
check_cmd() {
  command -v "$1" &>/dev/null || fail "'$1' not found — please install it first"
}

# ═════════════════════════════════════════════════════════════════════════════
banner

echo -e "  ${COLOR_DIM}Checking prerequisites...${RESET}"
check_cmd minikube
success "minikube   $(minikube version --short 2>/dev/null)"
check_cmd kubectl
success "kubectl    $(kubectl version --client --short 2>/dev/null | awk '{print $NF}')"
check_cmd docker
success "docker     $(docker version --format '{{.Client.Version}}' 2>/dev/null)"
success "kustomize  ${COLOR_DIM}(using kubectl built-in — no standalone binary needed)${RESET}"

# ══════════════════════════════════════════════════════════════════════════════
step 1 6 "Start Minikube"

minikube start --driver=docker --cpus=4 --memory=4096 --addons=metrics-server \
  && success "Minikube is running  $(minikube status | grep host | awk '{print $2}')" \
  || fail "Minikube failed to start"

# ══════════════════════════════════════════════════════════════════════════════
step 2 6 "Clean existing project resources"

echo ""
warn "This step deletes resources before every run to guarantee idempotency."
echo ""

info "Removing APISIX config Job ${COLOR_DIM}(Jobs are immutable — must delete before re-apply)${RESET}"
kubectl delete job apisix-config-job \
  -n gateway --ignore-not-found --wait=true 2>&1 \
  | sed "s/^/          ${COLOR_DIM}/" | sed "s/$/${RESET}/"

info "Removing gateway namespace workloads ${COLOR_DIM}(apisix, apisix-admin, etcd)${RESET}"
kubectl delete deployment apisix apisix-admin etcd \
  -n gateway --ignore-not-found 2>&1 \
  | sed "s/^/          ${COLOR_DIM}/" | sed "s/$/${RESET}/"

info "Removing services namespace workloads ${COLOR_DIM}(product-service)${RESET}"
kubectl delete deployment product-service \
  -n services --ignore-not-found 2>&1 \
  | sed "s/^/          ${COLOR_DIM}/" | sed "s/$/${RESET}/"

info "Removing project-managed ConfigMaps"
kubectl delete configmap apisix-config apisix-admin-config apisix-config-scripts \
  -n gateway --ignore-not-found 2>&1 \
  | sed "s/^/          ${COLOR_DIM}/" | sed "s/$/${RESET}/"

info "Waiting for old Pods to fully terminate..."
kubectl wait --for=delete pod \
  -l 'app in (apisix,apisix-admin,etcd)' \
  -n gateway --timeout=60s 2>/dev/null || true
kubectl wait --for=delete pod \
  -l app=product-service \
  -n services --timeout=60s 2>/dev/null || true

success "All previous resources removed"

# ══════════════════════════════════════════════════════════════════════════════
step 3 6 "Build product-service Docker image"

# Guard: npm ci (used in Dockerfile) requires package-lock.json.
# Generate it on the host if missing (e.g. fresh clone).
PKG_DIR="${REPO_ROOT}/apps/product-service"
if [[ ! -f "${PKG_DIR}/package-lock.json" ]]; then
  warn "package-lock.json not found — generating it now with npm install..."
  npm install --prefix "${PKG_DIR}" --silent \
    && success "package-lock.json created at apps/product-service/"\
    || fail "npm install failed — cannot build Docker image"
else
  success "package-lock.json present  ${COLOR_DIM}(npm ci will use it)${RESET}"
fi

eval "$(minikube docker-env)"
docker build -t product-service:latest "${REPO_ROOT}/apps/product-service/" \
  && success "Image ${COLOR_KEY}product-service:latest${RESET} built inside Minikube daemon" \
  || fail "Docker build failed"

# ══════════════════════════════════════════════════════════════════════════════
step 4 6 "Apply Kustomize overlay  (k8s/overlays/local)"

kubectl apply -k "${REPO_ROOT}/k8s/overlays/local" \
  | sed "s/^/     /" \
  | sed -E "s/(configured|created|unchanged)/$(printf "${COLOR_OK}")&$(printf "${RESET}")/g"
echo ""
success "Manifests applied"

# ══════════════════════════════════════════════════════════════════════════════
step 5 6 "Wait for Deployments & config Job"

echo ""
for item in "etcd/gateway" "apisix/gateway" "apisix-admin/gateway" "product-service/services"; do
  dep="${item%%/*}"
  ns="${item##*/}"
  info "Rollout: ${COLOR_KEY}${dep}${RESET}  ${COLOR_DIM}(ns: ${ns})${RESET}"
  kubectl rollout status deployment/"${dep}" -n "${ns}" --timeout=120s \
    | sed "s/^/          /" \
    | sed -E "s/(successfully rolled out)/$(printf "${COLOR_OK}")&$(printf "${RESET}")/g"
done

echo ""
info "Waiting for APISIX config Job to complete..."
kubectl wait --for=condition=complete job/apisix-config-job \
  -n gateway --timeout=30s \
  && success "Config Job finished — routes & consumers are live" \
  || fail "Config Job did not complete within 0.5 minutes.  Run: kubectl logs -n gateway job/apisix-config-job"

# ══════════════════════════════════════════════════════════════════════════════
step 6 6 "Verification"

NODE_IP=$(minikube ip)
TOTAL=$(elapsed)

echo ""
echo -e "  ${COLOR_OK}${BOLD}Deployment complete in ${TOTAL}${RESET}"
echo ""
echo -e "  ${BOLD}${WHITE}╭─────────────────────────────────────────────────────────────╮${RESET}"
echo -e "  ${BOLD}${WHITE}│${RESET}  ${BOLD}Node IP:${RESET}  ${COLOR_KEY}${NODE_IP}${RESET}"
echo -e "  ${BOLD}${WHITE}│${RESET}"
echo -e "  ${BOLD}${WHITE}│${RESET}  ${COLOR_HEAD}🌐  PUBLIC ROUTE${RESET}  ${COLOR_DIM}(port 9080 · no auth)${RESET}"
echo -e "  ${BOLD}${WHITE}│${RESET}  ${COLOR_CMD}curl -s http://${NODE_IP}:30080/external/products | jq .${RESET}"
echo -e "  ${BOLD}${WHITE}│${RESET}"
echo -e "  ${BOLD}${WHITE}│${RESET}  ${COLOR_HEAD}🔑  INTERNAL ROUTE${RESET}  ${COLOR_DIM}(port 9081 · API key required)${RESET}"
echo -e "  ${BOLD}${WHITE}│${RESET}  ${COLOR_CMD}curl -s \\${RESET}"
echo -e "  ${BOLD}${WHITE}│${RESET}  ${COLOR_CMD}  -H 'X-API-KEY: ${INTERNAL_API_KEY}' \\${RESET}"
echo -e "  ${BOLD}${WHITE}│${RESET}  ${COLOR_CMD}  http://${NODE_IP}:30081/internal/products/admin | jq .${RESET}"
echo -e "  ${BOLD}${WHITE}│${RESET}"
echo -e "  ${BOLD}${WHITE}│${RESET}  ${COLOR_HEAD}🔒  SECURITY — must return 404, not 401${RESET}"
echo -e "  ${BOLD}${WHITE}│${RESET}  ${COLOR_DIM}# Unauthorized access hides route existence:${RESET}"
echo -e "  ${BOLD}${WHITE}│${RESET}  ${COLOR_CMD}curl -sv http://${NODE_IP}:30081/internal/products/admin \\${RESET}"
echo -e "  ${BOLD}${WHITE}│${RESET}  ${COLOR_CMD}  2>&1 | grep '< HTTP'${RESET}"
echo -e "  ${BOLD}${WHITE}│${RESET}"
echo -e "  ${BOLD}${WHITE}│${RESET}  ${COLOR_HEAD}🚧  PORT ISOLATION — internal route blocked on port 9080${RESET}"
echo -e "  ${BOLD}${WHITE}│${RESET}  ${COLOR_CMD}curl -sv http://${NODE_IP}:30080/internal/products/admin \\${RESET}"
echo -e "  ${BOLD}${WHITE}│${RESET}  ${COLOR_CMD}  2>&1 | grep '< HTTP'${RESET}"
echo -e "  ${BOLD}${WHITE}╰─────────────────────────────────────────────────────────────╯${RESET}"
echo ""
