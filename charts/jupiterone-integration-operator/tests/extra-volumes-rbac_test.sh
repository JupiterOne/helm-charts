#!/usr/bin/env bash
set -euo pipefail

# Requires helm and yq (mikefarah v4).

CHART_DIR="helm-charts/charts/jupiterone-integration-operator"
PASSED=0
FAILED=0

if [ ! -d "$CHART_DIR" ]; then
  echo "ERROR: Run this script from the repository root"
  echo "  Expected chart directory: $CHART_DIR"
  exit 1
fi

pass() {
  echo "  PASS: $1"
  PASSED=$((PASSED + 1))
}

fail() {
  echo "  FAIL: $1"
  [ -z "${2:-}" ] || echo "    $2"
  FAILED=$((FAILED + 1))
}

assert_eq() {
  local description="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$description"
  else
    fail "$description" "expected: $expected, got: $actual"
  fi
}

run_test() {
  local name="$1"
  shift
  echo ""
  echo "=== Test: $name ==="
  "$@"
}

render() {
  helm template test "$CHART_DIR" --namespace jupiterone "$@"
}

deployment() {
  yq -N 'select(.kind == "Deployment")' <<<"$1"
}

volume_names() {
  deployment "$1" | yq -N -r '[.spec.template.spec.volumes[].name] | join(",")'
}

mount_names() {
  deployment "$1" | yq -N -r '[.spec.template.spec.containers[0].volumeMounts[].name] | join(",")'
}

EXTRA=(
  --set 'controllerManager.extraVolumes[0].name=sigstore'
  --set 'controllerManager.extraVolumes[0].configMap.name=sigstore-trusted-root'
  --set 'controllerManager.extraVolumeMounts[0].name=sigstore'
  --set 'controllerManager.extraVolumeMounts[0].mountPath=/etc/sigstore'
  --set 'controllerManager.extraVolumeMounts[0].readOnly=true'
)

test_no_volumes_by_default() {
  local output
  output=$(render)
  assert_eq "no pod volumes by default" "null" \
    "$(deployment "$output" | yq -N -r '.spec.template.spec.volumes')"
  assert_eq "no container volumeMounts by default" "null" \
    "$(deployment "$output" | yq -N -r '.spec.template.spec.containers[0].volumeMounts')"
}

test_extra_volumes_rendered() {
  local output
  output=$(render "${EXTRA[@]}")
  assert_eq "extra volume rendered" "sigstore" "$(volume_names "$output")"
  assert_eq "extra volume keeps its source" "sigstore-trusted-root" \
    "$(deployment "$output" | yq -N -r '.spec.template.spec.volumes[0].configMap.name')"
  assert_eq "extra volumeMount rendered" "sigstore" "$(mount_names "$output")"
  assert_eq "extra volumeMount path" "/etc/sigstore" \
    "$(deployment "$output" | yq -N -r '.spec.template.spec.containers[0].volumeMounts[0].mountPath')"
  assert_eq "extra volumeMount readOnly" "true" \
    "$(deployment "$output" | yq -N -r '.spec.template.spec.containers[0].volumeMounts[0].readOnly')"
}

test_extra_volumes_with_metrics_certs() {
  local output
  output=$(render "${EXTRA[@]}" --set certmanager.enable=true --set metrics.enable=true)
  assert_eq "metrics-certs and extra volume both rendered" "metrics-certs,sigstore" "$(volume_names "$output")"
  assert_eq "metrics-certs and extra volumeMount both rendered" "metrics-certs,sigstore" "$(mount_names "$output")"
}

test_metrics_certs_unchanged() {
  local output
  output=$(render --set certmanager.enable=true --set metrics.enable=true)
  assert_eq "metrics-certs volume alone" "metrics-certs" "$(volume_names "$output")"
  assert_eq "metrics-certs volumeMount alone" "metrics-certs" "$(mount_names "$output")"
}

test_role_reads_serviceaccounts() {
  local output
  output=$(render)
  assert_eq "manager Role grants only get on serviceaccounts" "get" \
    "$(yq -N -r 'select(.kind == "Role" and .metadata.name == "jupiterone-integration-operator-manager-role")
      | .rules[] | select(.apiGroups[0] == "" and (.resources[] == "serviceaccounts")) | .verbs | join(",")' <<<"$output")"
}

run_test "No extra volumes by default" test_no_volumes_by_default
run_test "extraVolumes and extraVolumeMounts rendered" test_extra_volumes_rendered
run_test "extraVolumes alongside metrics-certs" test_extra_volumes_with_metrics_certs
run_test "metrics-certs without extraVolumes" test_metrics_certs_unchanged
run_test "Manager Role reads ServiceAccounts" test_role_reads_serviceaccounts

echo ""
echo "=============================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=============================="
[ "$FAILED" -eq 0 ] || exit 1
