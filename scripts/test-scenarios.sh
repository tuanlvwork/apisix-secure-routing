#!/usr/bin/env bash
# =============================================================================
# test-scenarios.sh — Automated test suite for dual-network APISIX routing.
# =============================================================================
set -euo pipefail

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
BG_GREEN="\033[42m"
BG_RED="\033[41m"

# Semantic aliases
COLOR_STEP="${BOLD}${CYAN}"
COLOR_OK="${BOLD}${GREEN}"
COLOR_WARN="${BOLD}${YELLOW}"
COLOR_ERR="${BOLD}${RED}"
COLOR_DIM="${DIM}${WHITE}"
COLOR_KEY="${BOLD}${MAGENTA}"

# ── Helper printers ───────────────────────────────────────────────────────────
banner() {
  echo ""
  echo -e "${BOLD}${BG_BLUE}${WHITE}                                                              ${RESET}"
  echo -e "${BOLD}${BG_BLUE}${WHITE}   ████████╗███████╗███████╗████████╗                         ${RESET}"
  echo -e "${BOLD}${BG_BLUE}${WHITE}   ╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝                         ${RESET}"
  echo -e "${BOLD}${BG_BLUE}${WHITE}      ██║   █████╗  ███████╗   ██║                            ${RESET}"
  echo -e "${BOLD}${BG_BLUE}${WHITE}      ██║   ██╔══╝  ╚════██║   ██║                            ${RESET}"
  echo -e "${BOLD}${BG_BLUE}${WHITE}      ██║   ███████╗███████║   ██║                            ${RESET}"
  echo -e "${BOLD}${BG_BLUE}${WHITE}      ╚═╝   ╚══════╝╚══════╝   ╚═╝                            ${RESET}"
  echo -e "${BOLD}${BG_BLUE}${WHITE}                                                              ${RESET}"
  echo -e "${BOLD}${BG_CYAN}${BLACK}        Automated Validation Suite  ·  APISIX Routing         ${RESET}"
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
  echo -e "  ${COLOR_STEP}▶  SCENARIO ${num}/${total}${RESET}  ${BOLD}${label}${RESET}"
  divider
}

info()    { echo -e "     ${COLOR_DIM}→${RESET}  $*"; }
success() { echo -e "     ${COLOR_OK}✔${RESET}  $*"; }
warn()    { echo -e "     ${COLOR_WARN}⚠${RESET}  $*"; }
fail()    { echo -e "     ${COLOR_ERR}✘  ERROR: $*${RESET}" >&2; exit 1; }

test_pass() { echo -e "     ${BG_GREEN}${BLACK}${BOLD} PASS ${RESET} $*"; }
test_fail() { echo -e "     ${BG_RED}${WHITE}${BOLD} FAIL ${RESET} $*" >&2; exit 1; }

# ── Setup ─────────────────────────────────────────────────────────────────────
MINIKUBE_PROFILE="apisix-secure-routing"
NODE_IP="127.0.0.1"

EXT_PORT=30080
INT_PORT=30081
API_KEY="internal-secret-key-CHANGE-IN-PRODUCTION"

EXT_URI="http://${NODE_IP}:${EXT_PORT}"
INT_URI="http://${NODE_IP}:${INT_PORT}"

# ═════════════════════════════════════════════════════════════════════════════
banner

echo -e "  ${COLOR_DIM}Target Environment:${RESET}"
echo -e "    Target Host:   ${COLOR_KEY}localhost (via port-forward)${RESET}"
echo -e "    Public Port:   ${COLOR_KEY}${EXT_PORT}${RESET}"
echo -e "    Internal Port: ${COLOR_KEY}${INT_PORT}${RESET}"

# ═════════════════════════════════════════════════════════════════════════════
step 1 6 "Pre-flight & Port-Forwarding"

info "Checking if Minikube profile '${MINIKUBE_PROFILE}' is running..."
if ! minikube -p "${MINIKUBE_PROFILE}" status >/dev/null 2>&1; then
  fail "Minikube is not running. Please launch it or run scripts/bootstrap.sh"
fi

info "Checking if APISIX is deployed..."
if ! kubectl get service apisix-external -n gateway > /dev/null 2>&1; then
  fail "APISIX service (apisix-external) not found. Please run scripts/bootstrap.sh first."
fi
if ! kubectl get service apisix-internal -n gateway > /dev/null 2>&1; then
  fail "APISIX service (apisix-internal) not found. Please run scripts/bootstrap.sh first."
fi

info "Establishing background port-forwarding to APISIX..."
# Keep our local environment clean by killing the port-forwards upon script exit
trap 'kill $(jobs -p) 2>/dev/null || true' EXIT

kubectl port-forward -n gateway svc/apisix-external ${EXT_PORT}:9080 > /dev/null 2>&1 &
kubectl port-forward -n gateway svc/apisix-internal ${INT_PORT}:9081 > /dev/null 2>&1 &

sleep 3
success "Port-forwards active to localhost:${EXT_PORT} and localhost:${INT_PORT}"

# ═════════════════════════════════════════════════════════════════════════════
step 2 6 "Public Endpoint Validation"

info "Testing public route (no authentication)"
info "GET ${EXT_URI}/external/products"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${EXT_URI}/external/products")

if [ "$STATUS" == "200" ]; then
    test_pass "Route mapped successfully (HTTP 200)"
else
    test_fail "Expected HTTP 200, got ${STATUS}"
fi

# ═════════════════════════════════════════════════════════════════════════════
step 3 6 "Namespace & Port Isolation"

info "Testing namespace overlap (public port -> internal namespace)"
info "GET ${EXT_URI}/external/internal/products"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${EXT_URI}/external/internal/products")

if [ "$STATUS" == "404" ]; then
    test_pass "Internal namespace protected from public port (HTTP 404)"
else
    test_fail "Expected HTTP 404, got ${STATUS}"
fi

info "Testing unmapped path on public port"
info "GET ${EXT_URI}/internal/products"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${EXT_URI}/internal/products")

if [ "$STATUS" == "404" ]; then
    test_pass "Port binding blocked direct internal access (HTTP 404)"
else
    test_fail "Expected HTTP 404, got ${STATUS}"
fi

# ═════════════════════════════════════════════════════════════════════════════
step 4 6 "Internal Endpoint Validation (Valid Auth)"

info "Testing internal route with valid X-API-KEY"
info "GET ${INT_URI}/internal/products"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "X-API-KEY: ${API_KEY}" "${INT_URI}/internal/products")

if [ "$STATUS" == "200" ]; then
    test_pass "Internal API authenticated and successfully routed (HTTP 200)"
else
    test_fail "Expected HTTP 200, got ${STATUS}"
fi

# ═════════════════════════════════════════════════════════════════════════════
step 5 6 "Route Stealth Security"

info "Testing internal route with NO authentication"
info "GET ${INT_URI}/internal/products"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${INT_URI}/internal/products")

if [ "$STATUS" == "404" ]; then
    test_pass "Missing credentials returned HTTP 404 Not Found (Stealth Active)"
else
    test_fail "Stealth Check Failed. Expected HTTP 404, got ${STATUS}"
fi

info "Testing internal route with INVALID authentication"
info "GET ${INT_URI}/internal/products    (Header: X-API-KEY: bad-key-123)"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "X-API-KEY: bad-key-123" "${INT_URI}/internal/products")

if [ "$STATUS" == "404" ]; then
    test_pass "Invalid credentials returned HTTP 404 Not Found (Stealth Active)"
else
    test_fail "Stealth Check Failed. Expected HTTP 404, got ${STATUS}"
fi

# ═════════════════════════════════════════════════════════════════════════════
step 6 6 "Consumer Rate Limiting (limit-count plugin)"

info "Flooding internal route to trigger rate limit quotas (50 requests / 60s)..."

LIMIT_HIT=false
# Fire 55 requests in a loop
for i in {1..55}; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "X-API-KEY: ${API_KEY}" "${INT_URI}/internal/products")
    
    if [ "$STATUS" == "429" ]; then
        LIMIT_HIT=true
        success "Request #${i} returned HTTP 429 Too Many Requests"
        break
    fi
    
    # Optional print every 10 loops for visual progress
    if (( i % 10 == 0 )); then
        info "Sent ${i} requests..."
    fi
done

if [ "$LIMIT_HIT" = true ]; then
    test_pass "Rate limiter successfully engaged (HTTP 429)"
else
    test_fail "Rate limiter failed to engage. All 55 requests returned HTTP 200"
fi

# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "  ${BG_GREEN}${BLACK}${BOLD} DONE ${RESET} ${COLOR_OK}All Test Scenarios Passed Successfully!${RESET}"
echo ""
