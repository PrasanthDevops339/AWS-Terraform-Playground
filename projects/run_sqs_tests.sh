#!/usr/bin/env bash
# =============================================================================
# SQS SecureTransport Test Runner
#
# Runs all three test layers in order:
#   1. Unit tests      — no AWS, no terraform (always safe to run)
#   2. Integration: no-tls — baseline before SecureTransport policy
#   3. Integration: with-tls — prove policy is a no-op for HTTPS callers
#
# Usage:
#   ./run_sqs_tests.sh               # run all three layers
#   ./run_sqs_tests.sh unit          # unit tests only (no AWS required)
#   ./run_sqs_tests.sh no-tls        # no-tls integration only
#   ./run_sqs_tests.sh with-tls      # with-tls integration only
#
# Prerequisites for integration tests:
#   - terraform apply completed in the respective project directory
#   - Valid AWS credentials (env vars, profile, or EC2 role)
#   - pip install boto3  (or: pip install -r tests/requirements.txt)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODULE_TESTS="$REPO_ROOT/Terrafrom-AWS-Prasanth/terraform-aws-sqs/tests/test_policy_unit.py"
NO_TLS_TESTS="$SCRIPT_DIR/simple-sqs-no-tls/tests/test_sqs.py"
WITH_TLS_TESTS="$SCRIPT_DIR/simple-sqs-with-tls/tests/test_sqs.py"

OVERALL_PASS=0
OVERALL_FAIL=0

# ── helpers ──────────────────────────────────────────────────────────────────

divider() { printf '\n%s\n' "$(printf '=%.0s' {1..60})"; }

run_suite() {
    local label="$1"
    local script="$2"
    divider
    echo "  Running: $label"
    divider
    if python3 "$script"; then
        OVERALL_PASS=$((OVERALL_PASS + 1))
    else
        OVERALL_FAIL=$((OVERALL_FAIL + 1))
    fi
}

check_python() {
    if ! command -v python3 &>/dev/null; then
        echo "ERROR: python3 not found. Install Python 3.10+."
        exit 1
    fi
}

check_boto3() {
    if ! python3 -c "import boto3" &>/dev/null; then
        echo "ERROR: boto3 not installed."
        echo "       Run: pip install boto3"
        echo "       Or:  pip install -r tests/requirements.txt"
        exit 1
    fi
}

# ── main ─────────────────────────────────────────────────────────────────────

MODE="${1:-all}"

check_python

echo ""
echo "============================================================"
echo "  SQS SecureTransport — Test Suite"
echo "  Mode: $MODE"
echo "============================================================"

case "$MODE" in
  unit)
    run_suite "Unit tests — policy logic (no AWS)" "$MODULE_TESTS"
    ;;
  no-tls)
    check_boto3
    run_suite "Integration — simple-sqs-no-tls (baseline)" "$NO_TLS_TESTS"
    ;;
  with-tls)
    check_boto3
    run_suite "Integration — simple-sqs-with-tls (policy active)" "$WITH_TLS_TESTS"
    ;;
  all)
    run_suite "Unit tests — policy logic (no AWS)" "$MODULE_TESTS"
    check_boto3
    run_suite "Integration — simple-sqs-no-tls (baseline)" "$NO_TLS_TESTS"
    run_suite "Integration — simple-sqs-with-tls (policy active)" "$WITH_TLS_TESTS"
    ;;
  *)
    echo "Unknown mode '$MODE'. Use: unit | no-tls | with-tls | all"
    exit 1
    ;;
esac

# ── final summary ─────────────────────────────────────────────────────────────

divider
echo "  Overall Summary"
divider
TOTAL=$((OVERALL_PASS + OVERALL_FAIL))
echo "  Suites passed: $OVERALL_PASS / $TOTAL"

if [[ $OVERALL_FAIL -eq 0 ]]; then
    echo ""
    echo "  All test suites passed."
    if [[ "$MODE" == "all" || "$MODE" == "with-tls" ]]; then
        echo ""
        echo "  CONCLUSION: SecureTransport deny policy is safe to roll out."
        echo "              Standard SDK/CLI callers (HTTPS) are NOT affected."
    fi
    exit 0
else
    echo ""
    echo "  $OVERALL_FAIL suite(s) failed — review output above."
    exit 1
fi

