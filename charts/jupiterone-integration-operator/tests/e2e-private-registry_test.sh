#!/usr/bin/env bash
set -euo pipefail

# End-to-end validation test for the private registry pipeline.
# Validates that Helm values render correct env vars whose names match
# what the Go operator code reads (IMAGE_REGISTRY, IMAGE_PULL_SECRETS),
# and that the Deployment pod spec includes imagePullSecrets when configured.

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
  echo "=== E2E Test: $test_name ==="
  $test_func
}

# --- E2E Test cases ---

test_e2e_default_backwards_compat() {
  # Validates that default Helm values produce no private registry configuration,
  # preserving backwards compatibility. Also confirms that existing operator env
  # vars (JOB_TTL_SECONDS, WATCH_NAMESPACE) remain present.
  local output
  output=$(helm template test-release "$CHART_DIR")

  assert_not_contains "No IMAGE_REGISTRY env var in defaults" \
    "IMAGE_REGISTRY" "$output"
  assert_not_contains "No IMAGE_PULL_SECRETS env var in defaults" \
    "IMAGE_PULL_SECRETS" "$output"
  assert_not_contains "No imagePullSecrets in pod spec by default" \
    "imagePullSecrets" "$output"
  assert_contains "JOB_TTL_SECONDS still present (operator functionality intact)" \
    "JOB_TTL_SECONDS" "$output"
  assert_contains "WATCH_NAMESPACE still present (operator functionality intact)" \
    "WATCH_NAMESPACE" "$output"
}

test_e2e_image_registry_env_var() {
  # Validates that setting imageRegistry produces an IMAGE_REGISTRY env var
  # with the exact name the Go operator reads via os.LookupEnv("IMAGE_REGISTRY").
  local output
  output=$(helm template test-release "$CHART_DIR" \
    --set controllerManager.imageRegistry=registry.internal.corp.com)

  # Cross-repo contract: env var name must be IMAGE_REGISTRY (matches Go operator)
  assert_contains "IMAGE_REGISTRY env var name matches Go operator os.LookupEnv key" \
    "name: IMAGE_REGISTRY" "$output"
  assert_contains "IMAGE_REGISTRY value flows through from Helm values" \
    'value: "registry.internal.corp.com"' "$output"

  # Negative checks: only imageRegistry was set
  assert_not_contains "No IMAGE_PULL_SECRETS when only imageRegistry is set" \
    "IMAGE_PULL_SECRETS" "$output"
  assert_not_contains "No imagePullSecrets in pod spec when only imageRegistry is set" \
    "imagePullSecrets:" "$output"
}

test_e2e_image_pull_secrets_flow() {
  # Validates that imagePullSecrets flows to both the pod spec (for kubelet)
  # and the IMAGE_PULL_SECRETS env var (for the Go operator to propagate to jobs).
  # The env var name must match what the Go code reads via os.Getenv("IMAGE_PULL_SECRETS").
  local output
  output=$(helm template test-release "$CHART_DIR" \
    --set 'controllerManager.imagePullSecrets[0].name=corp-registry-creds')

  # Pod spec: imagePullSecrets for the operator Deployment itself
  assert_contains "imagePullSecrets present in Deployment pod spec" \
    "imagePullSecrets:" "$output"
  assert_contains "Secret name rendered in pod spec" \
    "name: corp-registry-creds" "$output"

  # Cross-repo contract: env var name must be IMAGE_PULL_SECRETS (matches Go operator)
  assert_contains "IMAGE_PULL_SECRETS env var name matches Go operator os.Getenv key" \
    "name: IMAGE_PULL_SECRETS" "$output"

  # The env var value must be JSON-encoded (Go operator parses it as JSON)
  assert_contains "IMAGE_PULL_SECRETS value is JSON-encoded for Go operator parsing" \
    '[{\"name\":\"corp-registry-creds\"}]' "$output"

  # Negative: IMAGE_REGISTRY should not appear
  assert_not_contains "No IMAGE_REGISTRY when only imagePullSecrets is set" \
    "IMAGE_REGISTRY" "$output"
}

test_e2e_full_private_registry_config() {
  # Validates the complete private registry configuration with both values set.
  # This is the realistic enterprise scenario: custom registry + pull secrets.
  local output
  output=$(helm template test-release "$CHART_DIR" \
    --set controllerManager.imageRegistry=registry.internal.corp.com \
    --set 'controllerManager.imagePullSecrets[0].name=corp-registry-creds')

  # IMAGE_REGISTRY env var (Go operator reads this for image ref construction)
  assert_contains "IMAGE_REGISTRY env var present with both values set" \
    "name: IMAGE_REGISTRY" "$output"
  assert_contains "IMAGE_REGISTRY has correct registry value" \
    'value: "registry.internal.corp.com"' "$output"

  # IMAGE_PULL_SECRETS env var (Go operator reads this to propagate to job pods)
  assert_contains "IMAGE_PULL_SECRETS env var present with both values set" \
    "name: IMAGE_PULL_SECRETS" "$output"
  assert_contains "IMAGE_PULL_SECRETS JSON contains secret name" \
    'corp-registry-creds' "$output"

  # Pod spec imagePullSecrets (kubelet uses this to pull the operator image)
  assert_contains "imagePullSecrets in Deployment pod spec" \
    "imagePullSecrets:" "$output"

  # Existing env vars not clobbered by new configuration
  assert_contains "WATCH_NAMESPACE still present (not clobbered)" \
    "WATCH_NAMESPACE" "$output"
  assert_contains "JOB_TTL_SECONDS still present (not clobbered)" \
    "JOB_TTL_SECONDS" "$output"
}

test_e2e_multiple_image_pull_secrets() {
  # Validates the multi-secret scenario: two imagePullSecrets configured together.
  # Verifies both secrets appear in pod spec and in the JSON-encoded env var.
  local output
  output=$(helm template test-release "$CHART_DIR" \
    --set 'controllerManager.imagePullSecrets[0].name=cred-a' \
    --set 'controllerManager.imagePullSecrets[1].name=cred-b')

  # Both secrets in pod spec
  assert_contains "First secret in pod spec imagePullSecrets" \
    "name: cred-a" "$output"
  assert_contains "Second secret in pod spec imagePullSecrets" \
    "name: cred-b" "$output"

  # IMAGE_PULL_SECRETS env var contains both secrets in JSON
  assert_contains "IMAGE_PULL_SECRETS env var present for multiple secrets" \
    "name: IMAGE_PULL_SECRETS" "$output"
  assert_contains "JSON-encoded value contains first secret" \
    'cred-a' "$output"
  assert_contains "JSON-encoded value contains second secret" \
    'cred-b' "$output"
}

# --- Run all E2E tests ---

run_test "Default values preserve backwards compatibility" test_e2e_default_backwards_compat
run_test "imageRegistry flows through to IMAGE_REGISTRY env var" test_e2e_image_registry_env_var
run_test "imagePullSecrets flows to both pod spec and env var" test_e2e_image_pull_secrets_flow
run_test "Full private registry configuration (both values)" test_e2e_full_private_registry_config
run_test "Multiple imagePullSecrets" test_e2e_multiple_image_pull_secrets

# --- Summary ---

echo ""
echo "=============================="
echo "E2E Results: $PASSED passed, $FAILED failed"
echo "=============================="
[ "$FAILED" -eq 0 ] || exit 1
