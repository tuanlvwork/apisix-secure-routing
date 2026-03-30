#!/usr/bin/env bash
# =============================================================================
# rollout-config-job.sh — Re-run apisix-config-job after config changes
#
# Usage:
#   bash scripts/rollout-config-job.sh           # apply configmap + re-run job
#   bash scripts/rollout-config-job.sh --logs     # also stream logs until done
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JOB_NAME="apisix-config-job"
NS="gateway"
JOB_YAML="${REPO_ROOT}/k8s/base/apisix-config-job/job.yaml"
KUST_DIR="${REPO_ROOT}/k8s/base/apisix-config-job"
STREAM_LOGS=false

# ── Color helpers ─────────────────────────────────────────────────────────────
RESET="\033[0m"; BOLD="\033[1m"
GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; RED="\033[31m"
ok()   { echo -e "${BOLD}${GREEN}  ✔ $*${RESET}"; }
info() { echo -e "${BOLD}${CYAN}  → $*${RESET}"; }
warn() { echo -e "${BOLD}${YELLOW}  ⚠ $*${RESET}"; }
err()  { echo -e "${BOLD}${RED}  ✖ $*${RESET}" >&2; }

for arg in "$@"; do
  case "$arg" in
    --logs|-l) STREAM_LOGS=true ;;
    --help|-h)
      echo "Usage: $0 [--logs]"
      echo "  --logs, -l   Stream job logs until completion"
      exit 0 ;;
    *) err "Unknown option: $arg"; exit 1 ;;
  esac
done

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║     APISIX Config Job — Rollout              ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════╝${RESET}"
echo ""

# ── 1. Delete the existing job (Jobs are immutable) ──────────────────────────
info "Deleting existing job '${JOB_NAME}' (if present)..."
if kubectl get job "${JOB_NAME}" -n "${NS}" &>/dev/null; then
  kubectl delete job "${JOB_NAME}" -n "${NS}"
  # Wait for old pods to terminate
  kubectl wait --for=delete pod \
    -l "job-name=${JOB_NAME}" \
    -n "${NS}" \
    --timeout=30s 2>/dev/null || true
  ok "Old job deleted"
else
  warn "No existing job found — will create fresh"
fi

# ── 2. Apply changes via Kustomize (ConfigMap/Secrets/Job) ────────────────────
info "Applying Kustomize block for '${JOB_NAME}'..."
kubectl apply -k "${KUST_DIR}" | sed 's/^/     /'
ok "Resources applied and job created"

# ── 4. Wait for a pod to be scheduled ────────────────────────────────────────
info "Waiting for job pod to start..."
for i in $(seq 1 20); do
  POD=$(kubectl get pods -n "${NS}" -l "job-name=${JOB_NAME}" \
        --field-selector=status.phase!=Pending \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  [ -n "${POD}" ] && break
  sleep 2
done

if [ -z "${POD:-}" ]; then
  # Fallback: just wait for any pod, including Pending
  POD=$(kubectl get pods -n "${NS}" -l "job-name=${JOB_NAME}" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
fi

if [ -z "${POD:-}" ]; then
  err "No pod found for job '${JOB_NAME}' after waiting. Check events:"
  kubectl describe job "${JOB_NAME}" -n "${NS}" | tail -20
  exit 1
fi
ok "Pod: ${POD}"

# ── 5. Stream logs or just wait ───────────────────────────────────────────────
if ${STREAM_LOGS}; then
  echo ""
  info "Streaming logs (Ctrl-C to detach, job will keep running)..."
  echo "──────────────────────────────────────────────────────"
  kubectl logs -n "${NS}" -f "job/${JOB_NAME}" 2>/dev/null || \
    kubectl logs -n "${NS}" -f "${POD}" 2>/dev/null
  echo "──────────────────────────────────────────────────────"
else
  info "Waiting for job to complete (timeout 120s)..."
  if kubectl wait job "${JOB_NAME}" -n "${NS}" \
      --for=condition=complete --timeout=120s 2>/dev/null; then
    ok "Job completed successfully!"
  else
    # Check if it failed
    FAILED=$(kubectl get job "${JOB_NAME}" -n "${NS}" \
              -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
    if [ "${FAILED}" != "" ] && [ "${FAILED}" -gt 0 ]; then
      err "Job failed after ${FAILED} attempt(s). Last logs:"
      kubectl logs -n "${NS}" "job/${JOB_NAME}" --tail=30 2>/dev/null || true
      exit 1
    fi
    warn "Timed out waiting — job may still be running. Check with:"
    warn "  kubectl logs -n ${NS} job/${JOB_NAME} -f"
  fi
fi

# ── 6. Summary ────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}  Job status:${RESET}"
kubectl get job "${JOB_NAME}" -n "${NS}" \
  -o custom-columns='NAME:.metadata.name,COMPLETIONS:.status.completionTime,SUCCEEDED:.status.succeeded,FAILED:.status.failed'
echo ""
echo -e "${BOLD}${CYAN}  View logs anytime:${RESET}"
echo "    kubectl logs -n ${NS} job/${JOB_NAME}"
echo ""
