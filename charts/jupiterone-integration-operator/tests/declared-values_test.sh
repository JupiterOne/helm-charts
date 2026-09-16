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

test_every_template_value_is_declared() {
  local referenced declared missing=""
  referenced=$(grep -rhoE '\.Values\.[A-Za-z0-9_.]+' "$CHART_DIR/templates" | sed 's/^\.Values\.//' | sort -u)
  declared=$(yq '[.. | path | join(".")] | .[]' "$CHART_DIR/values.yaml" | sed -E 's/\.[0-9]+//g' | grep -v '^$' | sort -u)

  for key in $referenced; do
    if ! echo "$declared" | grep -qE "^${key}(\.|$)"; then
      missing="$missing $key"
    fi
  done

  if [ -z "$missing" ]; then
    echo "  PASS: every .Values reference in templates is declared in values.yaml"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: undeclared values referenced by templates:$missing"
    FAILED=$((FAILED + 1))
  fi
}

test_pod_labels() {
  local output
  output=$(helm template test-release "$CHART_DIR" --set controllerManager.pod.labels.team=platform)

  assert_contains "pod label rendered" "team: platform" "$output"
}

test_name_override() {
  local output
  output=$(helm template test-release "$CHART_DIR" --set nameOverride=custom-operator)

  assert_contains "labels keep chart name (Chart.Name takes precedence)" "app.kubernetes.io/name: jupiterone-integration-operator" "$output"
}

test_operator_service_account_annotations() {
  local output
  output=$(helm template test-release "$CHART_DIR" \
    --set 'controllerManager.serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::123456789012:role/j1-operator')

  assert_contains "IRSA annotation on operator ServiceAccount" \
    "eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/j1-operator" "$output"
}

test_metrics_tls_names_match() {
  local output
  output=$(helm template test-release "$CHART_DIR" \
    --set prometheus.enable=true --set certmanager.enable=true --set crd.keep=true)

  assert_contains "ServiceMonitor serverName matches metrics Service" \
    "serverName: jupiterone-integration-operator-metrics-service.default.svc" "$output"
  assert_not_contains "No stale controller-manager-metrics-service serverName" \
    "controller-manager-metrics-service.default.svc" "$output"
  assert_contains "Certificate dnsNames include metrics Service" \
    "jupiterone-integration-operator-metrics-service.default.svc" "$output"
  assert_contains "crd.keep adds resource-policy keep" '"helm.sh/resource-policy": keep' "$output"
}

# --- Run all tests ---

run_test "Template references vs values.yaml" test_every_template_value_is_declared
run_test "controllerManager.pod.labels" test_pod_labels
run_test "nameOverride" test_name_override
run_test "controllerManager.serviceAccount.annotations" test_operator_service_account_annotations
run_test "Prometheus + cert-manager TLS names" test_metrics_tls_names_match

# --- Summary ---

echo ""
echo "=============================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=============================="
[ "$FAILED" -eq 0 ] || exit 1
