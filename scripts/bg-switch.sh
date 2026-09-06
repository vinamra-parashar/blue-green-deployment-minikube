#!/usr/bin/env bash
# =============================================================================
#  bg-switch.sh — Blue-Green Deployment Traffic Switch Script
#
#  Usage:
#    ./scripts/bg-switch.sh blue    # Switch production to Blue
#    ./scripts/bg-switch.sh green   # Switch production to Green
#    ./scripts/bg-switch.sh status  # Show which slot is currently active
#
#  What it does:
#    1. Validates the TARGET deployment pods are Ready
#    2. Patches the active-service selector + targetPort atomically
#    3. Verifies the service endpoint is updated
#    4. Reports the new production URL
# =============================================================================

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
NAMESPACE="blue-green"
ACTIVE_SERVICE="frontend-active-service"
BLUE_APP="frontend-blue"
GREEN_APP="frontend-green"
BLUE_PORT=3100
GREEN_PORT=3200
PROD_NODE_PORT=30000
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── Color codes ───────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN_C='\033[0;32m'
BLUE_C='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
log()     { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN_C}[✓]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}$*${RESET}"; echo "$(echo "$*" | sed 's/./-/g')"; }

# ── Get current active slot ───────────────────────────────────────────────────
get_current_slot() {
  kubectl get service "$ACTIVE_SERVICE" -n "$NAMESPACE" \
    -o jsonpath='{.metadata.annotations.blue-green/active-slot}' 2>/dev/null || echo "unknown"
}

# ── Show status ───────────────────────────────────────────────────────────────
show_status() {
  header "Blue-Green Deployment Status"

  CURRENT=$(get_current_slot)
  MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "<minikube-ip>")

  echo ""
  log "Namespace      : ${NAMESPACE}"
  log "Active Service : ${ACTIVE_SERVICE}"
  log "Production URL : http://${MINIKUBE_IP}:${PROD_NODE_PORT}"
  echo ""

  if [[ "$CURRENT" == "blue" ]]; then
    echo -e "  Active Slot  : ${BLUE_C}${BOLD}🔵 BLUE${RESET} (port ${BLUE_PORT})"
    echo -e "  Idle   Slot  : ${GREEN_C}⚫ Green${RESET} (port ${GREEN_PORT}) — standby"
  elif [[ "$CURRENT" == "green" ]]; then
    echo -e "  Active Slot  : ${GREEN_C}${BOLD}🟢 GREEN${RESET} (port ${GREEN_PORT})"
    echo -e "  Idle   Slot  : ${BLUE_C}⚫ Blue${RESET} (port ${BLUE_PORT}) — standby"
  else
    warn "Active slot unknown. Deploy the active-service first:"
    warn "  kubectl apply -f k8s/blue-green-switch/active-service.yaml"
  fi

  echo ""
  log "Pod status:"
  kubectl get pods -n "$NAMESPACE" \
    -l "tier=frontend" \
    -o custom-columns='  NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status,DEPLOYMENT:.metadata.labels.deployment,IP:.status.podIP' \
    2>/dev/null || true
  echo ""
}

# ── Validate target deployment is healthy ─────────────────────────────────────
validate_target() {
  local TARGET_APP="$1"
  local TARGET_LABEL="$2"

  log "Validating ${TARGET_LABEL} deployment pods are Ready..."

  READY_COUNT=$(kubectl get pods -n "$NAMESPACE" \
    -l "app=${TARGET_APP}" \
    --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null \
    | grep -c "True" || echo "0")

  if [[ "$READY_COUNT" -lt 1 ]]; then
    error "${TARGET_LABEL} pods are NOT ready (found ${READY_COUNT} ready pods)."
    error "Cannot switch traffic to an unhealthy deployment — aborting."
    echo ""
    kubectl get pods -n "$NAMESPACE" -l "app=${TARGET_APP}" 2>/dev/null || true
    exit 1
  fi

  success "${READY_COUNT} ${TARGET_LABEL} pod(s) confirmed Ready — safe to switch."
}

# ── Perform the traffic switch ────────────────────────────────────────────────
do_switch() {
  local TARGET="$1"
  local TARGET_APP TARGET_PORT TARGET_COLOR

  if [[ "$TARGET" == "blue" ]]; then
    TARGET_APP="$BLUE_APP"
    TARGET_PORT=$BLUE_PORT
    TARGET_COLOR="${BLUE_C}🔵 BLUE${RESET}"
  else
    TARGET_APP="$GREEN_APP"
    TARGET_PORT=$GREEN_PORT
    TARGET_COLOR="${GREEN_C}🟢 GREEN${RESET}"
  fi

  CURRENT=$(get_current_slot)
  MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "<minikube-ip>")
  TARGET_UPPER=$(echo "$TARGET" | tr '[:lower:]' '[:upper:]')
  CURRENT_UPPER=$(echo "$CURRENT" | tr '[:lower:]' '[:upper:]')

  header "Blue-Green Switch: → ${TARGET_UPPER}"
  echo ""

  # ── Guard: already on target ────────────────────────────────────────────────
  if [[ "$CURRENT" == "$TARGET" ]]; then
    warn "Production is already on ${TARGET_UPPER}. No switch needed."
    show_status
    exit 0
  fi

  log "Current active slot : ${CURRENT_UPPER}"
  log "Switching to        : ${TARGET_UPPER}"
  echo ""

  # ── Step 1: Validate target is healthy ──────────────────────────────────────
  validate_target "$TARGET_APP" "${TARGET_UPPER}"
  echo ""

  # ── Step 2: Patch the production service ────────────────────────────────────
  log "Patching ${ACTIVE_SERVICE} selector and targetPort..."

  kubectl patch service "$ACTIVE_SERVICE" \
    -n "$NAMESPACE" \
    --type='json' \
    -p="[
      {\"op\":\"replace\",\"path\":\"/spec/selector/app\",\"value\":\"${TARGET_APP}\"},
      {\"op\":\"replace\",\"path\":\"/spec/ports/0/targetPort\",\"value\":${TARGET_PORT}},
      {\"op\":\"replace\",\"path\":\"/metadata/annotations/blue-green~1active-slot\",\"value\":\"${TARGET}\"},
      {\"op\":\"replace\",\"path\":\"/metadata/annotations/blue-green~1last-switched\",\"value\":\"${TIMESTAMP}\"}
    ]" 2>&1

  success "Service patched!"
  echo ""

  # ── Step 3: Verify endpoints updated ────────────────────────────────────────
  log "Verifying service endpoints..."
  sleep 2

  ENDPOINTS=$(kubectl get endpoints "$ACTIVE_SERVICE" -n "$NAMESPACE" \
    -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")

  if [[ -n "$ENDPOINTS" ]]; then
    success "Active endpoints: ${ENDPOINTS}"
  else
    warn "No endpoints registered yet — pods may still be initializing."
  fi

  echo ""

  # ── Step 4: Summary ──────────────────────────────────────────────────────────
  echo -e "${BOLD}════════════════════════════════════════════${RESET}"
  echo -e "  ${GREEN_C}✅ Switch Complete!${RESET}"
  echo -e "  Production now serving: ${TARGET_COLOR}"
  echo -e "  Production URL: ${BOLD}http://${MINIKUBE_IP}:${PROD_NODE_PORT}${RESET}"
  echo -e "${BOLD}════════════════════════════════════════════${RESET}"
  echo ""
  echo -e "  To rollback: ${YELLOW}./scripts/bg-switch.sh ${CURRENT}${RESET}"
  echo ""
}

# ── Entry point ───────────────────────────────────────────────────────────────
TARGET="${1:-}"

case "$TARGET" in
  blue)   do_switch "blue" ;;
  green)  do_switch "green" ;;
  status) show_status ;;
  *)
    echo ""
    echo -e "${BOLD}Blue-Green Deployment Switch Tool${RESET}"
    echo ""
    echo "  Usage:"
    echo "    $0 blue    — Switch production traffic to Blue (port ${BLUE_PORT})"
    echo "    $0 green   — Switch production traffic to Green (port ${GREEN_PORT})"
    echo "    $0 status  — Show which slot is currently active"
    echo ""
    show_status
    ;;
esac
