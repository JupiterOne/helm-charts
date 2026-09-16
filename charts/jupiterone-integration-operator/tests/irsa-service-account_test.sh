#!/usr/bin/env bash
set -euo pipefail

CHART_DIR="helm-charts/charts/jupiterone-integration-operator"
PASSED=0
FAILED=0

if [ ! -d "$CHART_DIR" ]; then
  echo "ERROR: Run this script from the repository root"
  echo "  Expected chart directory: $CHART_DIR"
  exit 1
fi

# --- Helper functions ---

assert_contains() {
  local description="$1"
  local needle="$2"
  local haystack="$3"

  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $description"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $description"
    echo "    Expected output to contain: $needle"
    FAILED=$((FAILED + 1))
  fi
}

assert_not_contains() {
  local description="$1"
  local needle="$2"
  local haystack="$3"

  if echo "$haystack" | grep -qF "$needle"; then
    echo "  FAIL: $description"
    echo "    Expected output NOT to contain: $needle"
    FAILED=$((FAILED + 1))
  else
    echo "  PASS: $description"
    PASSED=$((PASSED + 1))
  fi
}

run_test() {
  local test_name="$1"
  local test_func="$2"

  echo ""
  echo "=== Test: $test_name ==="
  $test_func
}

# --- Test cases ---

test_default_values() {
  local output
  output=$(helm template test-release "$CHART_DIR")

  assert_not_contains "No job ServiceAccount by default" \
    "name: jupiterone-integration-job" "$output"
  assert_not_contains "No INTEGRATION_JOB_SERVICE_ACCOUNT by default" \
    "INTEGRATION_JOB_SERVICE_ACCOUNT" "$output"
  assert_contains "Integration ServiceAccount still rendered" \
    "name: jupiterone" "$output"
}

test_integration_service_account_annotations() {
  local output
  output=$(helm template test-release "$CHART_DIR" \
    --set 'integration.serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::123456789012:role/j1-k8s')

  assert_contains "IRSA annotation on the kubernetes-managed ServiceAccount" \
    "eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/j1-k8s" "$output"
}

test_job_service_account_created() {
  local output
  output=$(helm template test-release "$CHART_DIR" \
    --set integration.jobServiceAccount.create=true \
    --set 'integration.jobServiceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::123456789012:role/j1-job')

  assert_contains "Job ServiceAccount created with the default name" \
    "name: jupiterone-integration-job" "$output"
  assert_contains "IRSA annotation on the job ServiceAccount" \
    "eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/j1-job" "$output"
  assert_contains "INTEGRATION_JOB_SERVICE_ACCOUNT env var name present" \
    "name: INTEGRATION_JOB_SERVICE_ACCOUNT" "$output"
  assert_contains "INTEGRATION_JOB_SERVICE_ACCOUNT value is correct" \
    'value: "jupiterone-integration-job"' "$output"
}

test_job_service_account_custom_name() {
  local output
  output=$(helm template test-release "$CHART_DIR" \
    --set integration.jobServiceAccount.create=true \
    --set integration.jobServiceAccount.name=sbom-runner)

  assert_contains "Job ServiceAccount uses the configured name" \
    "name: sbom-runner" "$output"
  assert_contains "INTEGRATION_JOB_SERVICE_ACCOUNT uses the configured name" \
    'value: "sbom-runner"' "$output"
}

test_job_service_account_externally_managed() {
  local output
  output=$(helm template test-release "$CHART_DIR" \
    --set integration.jobServiceAccount.create=false \
    --set integration.jobServiceAccount.name=externally-managed)

  assert_contains "Operator points at the externally managed ServiceAccount" \
    'value: "externally-managed"' "$output"
  assert_not_contains "Chart does not create the externally managed ServiceAccount" \
    "  name: externally-managed" "$output"
}

# --- Run all tests ---

run_test "Default values (backwards compatibility)" test_default_values
run_test "integration.serviceAccount.annotations set" test_integration_service_account_annotations
run_test "integration.jobServiceAccount created" test_job_service_account_created
run_test "integration.jobServiceAccount custom name" test_job_service_account_custom_name
run_test "integration.jobServiceAccount managed externally" test_job_service_account_externally_managed

# --- Summary ---

echo ""
echo "=============================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=============================="
[ "$FAILED" -eq 0 ] || exit 1
