#!/usr/bin/env bash
# ============================================================================
# OPA Policy Evaluator — EFS KMS Encryption at Rest
# ============================================================================
# Usage:
#   ./scripts/evaluate.sh <tfplan.json> [policy_dir]
#   ./scripts/evaluate.sh examples/tfplan_compliant.json policy/
#
# Exit codes:
#   0 = compliant
#   1 = policy violations found
#   2 = script error (missing deps, bad input)
# ============================================================================
set -euo pipefail

# --- Configuration ---
PLAN_FILE="${1:-}"
POLICY_DIR="${2:-policy}"
OPA_BIN="${OPA_BIN:-opa}"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Validation ---
if [[ -z "${PLAN_FILE}" ]]; then
    echo -e "${RED}ERROR: Usage: $0 <tfplan.json> [policy_dir]${NC}"
    exit 2
fi

if [[ ! -f "${PLAN_FILE}" ]]; then
    echo -e "${RED}ERROR: Plan file not found: ${PLAN_FILE}${NC}"
    exit 2
fi

if [[ ! -d "${POLICY_DIR}" ]]; then
    echo -e "${RED}ERROR: Policy directory not found: ${POLICY_DIR}${NC}"
    exit 2
fi

if ! command -v "${OPA_BIN}" &>/dev/null; then
    echo -e "${RED}ERROR: OPA not found. Install: https://www.openpolicyagent.org/docs/latest/#1-download-opa${NC}"
    exit 2
fi

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  OPA Policy Check: EFS KMS Encryption at Rest${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Plan file:  ${YELLOW}${PLAN_FILE}${NC}"
echo -e "  Policy dir: ${YELLOW}${POLICY_DIR}${NC}"
echo -e "  OPA ver:    ${YELLOW}$(${OPA_BIN} version | head -1)${NC}"
echo ""

# --- Evaluate ---
DENY_OUTPUT=$("${OPA_BIN}" eval \
    --data "${POLICY_DIR}" \
    --input "${PLAN_FILE}" \
    --format pretty \
    'data.terraform.efs.encryption.deny')

VIOLATION_COUNT=$("${OPA_BIN}" eval \
    --data "${POLICY_DIR}" \
    --input "${PLAN_FILE}" \
    --format raw \
    'data.terraform.efs.encryption.violation_count')

# --- Report ---
if [[ "${VIOLATION_COUNT}" -eq 0 ]]; then
    echo -e "${GREEN}✅ PASS: All EFS resources compliant with KMS encryption policy.${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}❌ FAIL: ${VIOLATION_COUNT} violation(s) found${NC}"
    echo ""
    echo "${DENY_OUTPUT}" | while IFS= read -r line; do
        echo -e "  ${RED}▸${NC} ${line}"
    done
    echo ""
    echo -e "${YELLOW}Fix violations above and re-run terraform plan.${NC}"
    exit 1
fi
