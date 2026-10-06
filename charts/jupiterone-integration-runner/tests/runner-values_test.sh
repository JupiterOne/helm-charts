#!/usr/bin/env bash
set -euo pipefail

CHART_DIR="helm-charts/charts/jupiterone-integration-runner"
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

assert_render_fails() {
  local description="$1"
  local needle="$2"
  shift 2

  local output
  if output=$(helm template test-release "$CHART_DIR" "$@" 2>&1); then
    echo "  FAIL: $description"
    echo "    Expected helm template to fail"
    FAILED=$((FAILED + 1))
  elif grep -qF -- "$needle" <<<"$output"; then
    echo "  PASS: $description"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $description"
    echo "    Expected error to contain: $needle"
    FAILED=$((FAILED + 1))
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

test_kubernetes_secret_created() {
  local output
  output=$(helm template test-release "$CHART_DIR" \
    --set accountID=acct-1 --set apiToken=tok)

  assert_contains "IntegrationRunner rendered" "kind: IntegrationRunner" "$output"
  assert_contains "accountId is quoted" 'accountId: "acct-1"' "$output"
  assert_contains "Secret created" "kind: Secret" "$output"
  assert_contains "Secret named by secretAPITokenName" "name: j1token" "$output"
  assert_contains "token base64 encoded" "token: dG9r" "$output"
  assert_not_contains "No apiTokenSource without a provider" "apiTokenSource:" "$output"
}

test_external_secret() {
  local output
  output=$(helm template test-release "$CHART_DIR" \
    --set accountID=acct-1 --set createSecret=false --set secretAPITokenName=external)

  assert_not_contains "No Secret when createSecret=false" "kind: Secret" "$output"
  assert_contains "Runner references external secret" "secretAPITokenName: external" "$output"
}

test_api_token_source_kubernetes() {
  local output
  output=$(helm template test-release "$CHART_DIR" \
    --set accountID=acct-1 --set createSecret=false \
    --set apiTokenSource.provider=kubernetes)

  assert_contains "provider kubernetes" "provider: kubernetes" "$output"
  assert_contains "kubernetes name defaults to secretAPITokenName" "name: j1token" "$output"
}

test_api_token_source_asm() {
  local output
  output=$(helm template test-release "$CHART_DIR" \
    --set accountID=acct-1 --set createSecret=false \
    --set apiTokenSource.provider=awsSecretsManager \
    --set apiTokenSource.awsSecretsManager.secretId=jupiterone/runner \
    --set apiTokenSource.awsSecretsManager.region=us-east-1 \
    --set apiTokenSource.awsSecretsManager.versionStage=AWSCURRENT)

  assert_contains "provider awsSecretsManager" "provider: awsSecretsManager" "$output"
  assert_contains "secretId rendered" "secretId: jupiterone/runner" "$output"
  assert_contains "region rendered" "region: us-east-1" "$output"
  assert_contains "versionStage rendered" "versionStage: AWSCURRENT" "$output"
}

test_validation() {
  assert_render_fails "Placeholder apiToken rejected" "apiToken is required" \
    --set accountID=acct-1
  assert_render_fails "Missing accountID rejected" "accountID is required" \
    --set apiToken=tok
  assert_render_fails "ASM provider without secretId rejected" "secretId is required" \
    --set accountID=acct-1 --set createSecret=false --set apiTokenSource.provider=awsSecretsManager
  assert_render_fails "Unknown provider rejected" "must be" \
    --set accountID=acct-1 --set createSecret=false --set apiTokenSource.provider=vault
}

assert_eq() {
  local description="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $description"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $description"
    echo "    expected: $expected"
    echo "    got:      $actual"
    FAILED=$((FAILED + 1))
  fi
}

# One object of the output as compact JSON with sorted keys (requires yq).
object_json() {
  yq -o=json -I=0 "select(.kind == \"$1\") | $2 | sort_keys(.)" <<<"$3"
}

test_common_metadata() {
  local output
  output=$(helm template test-release "$CHART_DIR" \
    --set accountID=acct-1 --set apiToken=tok \
    --set commonLabels.team=security \
    --set-string commonLabels.cost-center=1234 \
    --set commonLabels.job-name=x \
    --set commonAnnotations.note=hello \
    --set commonAnnotations.helm\\.sh/resource-policy=keep)

  local labels='{"cost-center":"1234","job-name":"x","team":"security"}'
  assert_eq "Labels on the Secret" "$labels" "$(object_json Secret .metadata.labels "$output")"
  assert_eq "Annotations on the Secret, helm.sh/ dropped" '{"note":"hello"}' "$(object_json Secret .metadata.annotations "$output")"
  assert_eq "Labels on the IntegrationRunner" "$labels" "$(object_json IntegrationRunner .metadata.labels "$output")"
  assert_eq "Annotations on the IntegrationRunner, helm.sh/ dropped" '{"note":"hello"}' "$(object_json IntegrationRunner .metadata.annotations "$output")"
  assert_eq "spec.commonLabels without keys the operator manages" '{"cost-center":"1234","team":"security"}' \
    "$(object_json IntegrationRunner .spec.commonLabels "$output")"
  assert_eq "spec.commonAnnotations, helm.sh/ dropped" '{"note":"hello"}' \
    "$(object_json IntegrationRunner .spec.commonAnnotations "$output")"
}

test_common_metadata_unset() {
  local output
  output=$(helm template test-release "$CHART_DIR" \
    --set accountID=acct-1 --set apiToken=tok)

  assert_not_contains "No labels by default" "labels:" "$output"
  assert_not_contains "No annotations by default" "annotations:" "$output"
  assert_not_contains "No spec.commonLabels by default (older CRDs lack it)" "commonLabels" "$output"

  # helm upgrade --reuse-values from chart 1.1.0 has neither value.
  output=$(helm template test-release "$CHART_DIR" \
    --set accountID=acct-1 --set apiToken=tok \
    --set commonLabels=null --set commonAnnotations=null 2>&1)
  assert_contains "Renders without commonLabels (--reuse-values)" "kind: IntegrationRunner" "$output"
}

# --- Run all tests ---

run_test "Kubernetes Secret created (default path)" test_kubernetes_secret_created
run_test "External Secret" test_external_secret
run_test "apiTokenSource kubernetes" test_api_token_source_kubernetes
run_test "apiTokenSource awsSecretsManager" test_api_token_source_asm
run_test "Validation" test_validation
run_test "commonLabels and commonAnnotations" test_common_metadata
run_test "commonLabels unset" test_common_metadata_unset

# --- Summary ---

echo ""
echo "=============================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=============================="
[ "$FAILED" -eq 0 ] || exit 1
