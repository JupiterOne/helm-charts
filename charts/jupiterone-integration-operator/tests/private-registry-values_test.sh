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

  assert_not_contains "No IMAGE_REGISTRY env var in default output" \
    "IMAGE_REGISTRY" "$output"
  assert_not_contains "No IMAGE_PULL_SECRETS env var in default output" \
    "IMAGE_PULL_SECRETS" "$output"
  assert_not_contains "No imagePullSecrets in default pod spec" \
    "imagePullSecrets" "$output"
  assert_not_contains "No DISABLE_IMAGE_SIGNATURE_CHECK in default output" \
    "DISABLE_IMAGE_SIGNATURE_CHECK" "$output"
  assert_contains "JOB_TTL_SECONDS env var present (sanity check)" \
    "JOB_TTL_SECONDS" "$output"
  assert_contains "WATCH_NAMESPACE env var present (sanity check)" \
    "WATCH_NAMESPACE" "$output"
}

test_image_registry() {
  local output
  output=$(helm template test-release "$CHART_DIR" \
    --set controllerManager.imageRegistry=myregistry.example.com)

  assert_contains "IMAGE_REGISTRY env var name present" \
    "name: IMAGE_REGISTRY" "$output"
  assert_contains "IMAGE_REGISTRY value is correct" \
    'value: "myregistry.example.com"' "$output"
  assert_not_contains "No IMAGE_PULL_SECRETS when only imageRegistry is set" \
    "IMAGE_PULL_SECRETS" "$output"
  assert_not_contains "No imagePullSecrets in pod spec when only imageRegistry is set" \
    "imagePullSecrets:" "$output"
}

test_image_pull_secrets() {
  local output
  output=$(helm template test-release "$CHART_DIR" \
    --set 'controllerManager.imagePullSecrets[0].name=my-registry-secret')

  assert_contains "imagePullSecrets present in pod spec" \
    "imagePullSecrets:" "$output"
  assert_contains "Secret name in pod spec imagePullSecrets" \
    "name: my-registry-secret" "$output"
  assert_contains "IMAGE_PULL_SECRETS env var name present" \
    "name: IMAGE_PULL_SECRETS" "$output"
  assert_contains "IMAGE_PULL_SECRETS contains JSON-encoded value" \
    '[{\"name\":\"my-registry-secret\"}]' "$output"
  assert_not_contains "No IMAGE_REGISTRY when only imagePullSecrets is set" \
    "IMAGE_REGISTRY" "$output"
}

test_both_values() {
  local output
  output=$(helm template test-release "$CHART_DIR" \
    --set controllerManager.imageRegistry=myregistry.example.com \
    --set 'controllerManager.imagePullSecrets[0].name=my-registry-secret')

  assert_contains "IMAGE_REGISTRY env var name present" \
    "name: IMAGE_REGISTRY" "$output"
  assert_contains "IMAGE_REGISTRY value is correct" \
    'value: "myregistry.example.com"' "$output"
  assert_contains "imagePullSecrets present in pod spec" \
    "imagePullSecrets:" "$output"
  assert_contains "IMAGE_PULL_SECRETS env var name present" \
    "name: IMAGE_PULL_SECRETS" "$output"
}

test_disable_signature_check() {
  local output
  output=$(helm template test-release "$CHART_DIR" \
    --set controllerManager.disableImageSignatureCheck=true)

  assert_contains "DISABLE_IMAGE_SIGNATURE_CHECK env var present" \
    "name: DISABLE_IMAGE_SIGNATURE_CHECK" "$output"
  assert_contains "DISABLE_IMAGE_SIGNATURE_CHECK value is true" \
    'value: "true"' "$output"
}

test_signature_check_false() {
  local output
  output=$(helm template test-release "$CHART_DIR" \
    --set controllerManager.disableImageSignatureCheck=false)

  assert_not_contains "No DISABLE_IMAGE_SIGNATURE_CHECK when false" \
    "DISABLE_IMAGE_SIGNATURE_CHECK" "$output"
}

# --- Run all tests ---

run_test "Default values (backwards compatibility)" test_default_values
run_test "imageRegistry set" test_image_registry
run_test "imagePullSecrets set" test_image_pull_secrets
run_test "Both values set" test_both_values
run_test "disableImageSignatureCheck true" test_disable_signature_check
run_test "disableImageSignatureCheck false" test_signature_check_false

# --- Summary ---

echo ""
echo "=============================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=============================="
[ "$FAILED" -eq 0 ] || exit 1
