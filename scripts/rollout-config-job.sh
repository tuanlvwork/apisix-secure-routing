#!/usr/bin/env bash
# =============================================================================
# rollout-config-job.sh — Re-run apisix config jobs after declarative config changes
#
# Usage:
#   bash scripts/rollout-config-job.sh                     # rollout both external and internal
#   bash scripts/rollout-config-job.sh --target external   # rollout external only
#   bash scripts/rollout-config-job.sh --target internal   # rollout internal only
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="gateway"
TARGET="all"

# ── Color helpers ─────────────────────────────────────────────────────────────
RESET="\033[0m"; BOLD="\033[1m"
GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; RED="\033[31m"
ok()   { echo -e "${BOLD}${GREEN}  ✔ $*${RESET}"; }
info() { echo -e "${BOLD}${CYAN}  → $*${RESET}"; }
warn() { echo -e "${BOLD}${YELLOW}  ⚠ $*${RESET}"; }
err()  { echo -e "${BOLD}${RED}  ✖ $*${RESET}" >&2; }

while [[ $# -gt 0 ]]; do
  case $1 in
    --target|-t)
      TARGET="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [--target external|internal|all]"
      exit 0
      ;;
    *)
      err "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [ "$TARGET" == "all" ]; then
  GATEWAYS=("external" "internal")
elif [ "$TARGET" == "external" ] || [ "$TARGET" == "internal" ]; then
  GATEWAYS=("$TARGET")
else
  err "Invalid target: $TARGET. Must be external, internal, or all."
  exit 1
fi

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║     APISIX Config Job Sync — Rollout         ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════╝${RESET}"
echo ""

for gw in "${GATEWAYS[@]}"; do
  JOB_NAME="apisix-config-job-${gw}"
  KUST_DIR="${REPO_ROOT}/k8s/base/platform/apisix/${gw}/apisix-config-job"

  info "Processing gateway: ${BOLD}${gw}${RESET}"

  # ── 1. Delete the existing job (Jobs are immutable) ──────────────────────────
  if kubectl get job "${JOB_NAME}" -n "${NS}" &>/dev/null; then
    kubectl delete job "${JOB_NAME}" -n "${NS}" > /dev/null
    # Wait for old pods to terminate
    kubectl wait --for=delete pod -l "job-name=${JOB_NAME}" -n "${NS}" --timeout=30s 2>/dev/null || true
    ok "Old job deleted"
  fi

  # ── 2. Apply changes via Kustomize ──────────────────────────────────────────
  info "Applying declarative JSON configuration..."
  kubectl apply -k "${KUST_DIR}" > /dev/null
  ok "Resources applied and job created"

  # ── 3. Wait for job to complete ─────────────────────────────────────────────
  info "Waiting for job to complete (timeout 90s)..."
  if kubectl wait job "${JOB_NAME}" -n "${NS}" --for=condition=complete --timeout=90s 2>/dev/null; then
    ok "Job completed successfully!"
    echo "    Logs excerpt:"
    kubectl logs -n "${NS}" "job/${JOB_NAME}" | tail -n 8 | sed 's/^/      /'
  else
    err "Job failed or timed out. Last logs:"
    kubectl logs -n "${NS}" "job/${JOB_NAME}" --tail=30 2>/dev/null || true
    exit 1
  fi
  echo ""
done

ok "All requested configurations are synced!"
echo ""
