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

  if grep -qF -- "$needle" <<<"$haystack"; then
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

  if grep -qF -- "$needle" <<<"$haystack"; then
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

manager() {
  helm template test-release "$CHART_DIR" -s templates/manager/manager.yaml "$@"
}

test_default_values() {
  local output
  output=$(manager)

  assert_not_contains "No JOB_OVERRIDES env var by default" "JOB_OVERRIDES" "$output"
  assert_not_contains "No manager nodeSelector by default" "nodeSelector:" "$output"
  assert_not_contains "No manager tolerations by default" "tolerations:" "$output"
  assert_not_contains "No manager affinity by default" "affinity:" "$output"
  assert_contains "Default-container annotation kept" \
    "kubectl.kubernetes.io/default-container: manager" "$output"
}

test_job_overrides_json() {
  local output
  output=$(manager \
    --set controllerManager.job.labels.team=security \
    --set controllerManager.job.podLabels.cost-center=1234 \
    --set 'controllerManager.job.tolerations[0].key=dedicated' \
    --set 'controllerManager.job.tolerations[0].operator=Exists')

  assert_contains "JOB_OVERRIDES env var present" "name: JOB_OVERRIDES" "$output"
  assert_contains "Labels rendered" '\"labels\":{\"team\":\"security\"}' "$output"
  assert_contains "Numeric label value rendered as a string" '\"podLabels\":{\"cost-center\":\"1234\"}' "$output"
  assert_contains "Tolerations rendered" '\"tolerations\":[{\"key\":\"dedicated\",\"operator\":\"Exists\"}]' "$output"
  assert_not_contains "Empty keys omitted" '\"annotations\"' "$output"
  assert_not_contains "Empty affinity omitted" '\"affinity\"' "$output"
}

test_job_overrides_numeric_from_values_file() {
  local values output
  values=$(mktemp)
  printf 'controllerManager:\n  job:\n    podLabels:\n      cost-center: 1234\n' >"$values"
  output=$(manager -f "$values")
  rm -f "$values"

  assert_contains "Unquoted number from a values file is a string" '\"cost-center\":\"1234\"' "$output"
}

test_job_overrides_unknown_key_passed_through() {
  local output
  output=$(manager --set controllerManager.job.podLabel.team=security)

  assert_contains "Unknown key reaches the operator so it rejects the typo" '\"podLabel\":{\"team\":\"security\"}' "$output"
}

test_manager_metadata_and_scheduling() {
  local output
  output=$(manager \
    --set controllerManager.deployment.labels.team=security \
    --set controllerManager.deployment.annotations.owner=sec \
    --set controllerManager.pod.annotations.sidecar\\.istio\\.io/inject=false \
    --set controllerManager.pod.annotations.kubectl\\.kubernetes\\.io/default-container=other \
    --set controllerManager.nodeSelector.pool=tools \
    --set 'controllerManager.tolerations[0].key=dedicated' \
    --set 'controllerManager.tolerations[0].operator=Exists' \
    --set controllerManager.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key=zone \
    --set controllerManager.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator=Exists)

  assert_contains "Deployment label" '    team: "security"' "$output"
  assert_contains "Deployment annotation" '    owner: "sec"' "$output"
  assert_contains "Pod annotation" 'sidecar.istio.io/inject: "false"' "$output"
  assert_contains "Default-container annotation not overridden" \
    "kubectl.kubernetes.io/default-container: manager" "$output"
  assert_not_contains "Duplicate default-container annotation not rendered" \
    'kubectl.kubernetes.io/default-container: "other"' "$output"
  assert_contains "Manager nodeSelector" "      nodeSelector:
        pool: tools" "$output"
  assert_contains "Manager tolerations" "      tolerations:
        - key: dedicated" "$output"
  assert_contains "Manager affinity" "      affinity:
        nodeAffinity:" "$output"
}

test_events_rbac() {
  local output
  output=$(helm template test-release "$CHART_DIR" -s templates/rbac/role.yaml)

  assert_contains "Manager Role can create events" "  - events
  verbs:
  - create
  - patch" "$output"
}

# --- Run all tests ---

run_test "Default values (backwards compatibility)" test_default_values
run_test "JOB_OVERRIDES JSON" test_job_overrides_json
run_test "JOB_OVERRIDES numeric value from a values file" test_job_overrides_numeric_from_values_file
run_test "JOB_OVERRIDES unknown key" test_job_overrides_unknown_key_passed_through
run_test "Manager metadata and scheduling" test_manager_metadata_and_scheduling
run_test "Events RBAC" test_events_rbac

# --- Summary ---

echo ""
echo "=============================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=============================="
[ "$FAILED" -eq 0 ] || exit 1
