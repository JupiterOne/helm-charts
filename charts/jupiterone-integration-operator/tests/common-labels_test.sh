#!/usr/bin/env bash
# commonLabels / commonAnnotations reach every object the chart renders, and
# the runtime values the operator reads (JOB_OVERRIDES, COMMON_LABELS).
# Requires helm and yq (mikefarah v4).
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

# Every toggle that adds objects is on, so every template is checked.
render() {
  helm template test "$CHART_DIR" --namespace jupiterone \
    --set prometheus.enable=true \
    --set networkPolicy.enable=true \
    --set certmanager.enable=true \
    --set metrics.enable=true \
    --set integration.create=true \
    --set integration.jobServiceAccount.create=true \
    "$@"
}

COMMON=(
  --set commonLabels.team=remitly
  --set-string commonLabels.cost-center=1234
  --set commonLabels.control-plane=hijack
  --set commonLabels.job-name=hijack
  --set commonAnnotations.note=hello
  --set commonAnnotations.helm\\.sh/resource-policy=keep
)

# env value of the manager container, as JSON (empty when unset)
manager_env() {
  yq -N -r "select(.kind == \"Deployment\") | .spec.template.spec.containers[0].env[] | select(.name == \"$2\") | .value" <<<"$1"
}

# The raw text of the Deployment document.
deployment_doc() {
  awk '/^---/ { if (doc ~ /\nkind: Deployment\n/) print doc; doc = "" ; next } { doc = doc "\n" $0 } END { if (doc ~ /\nkind: Deployment\n/) print doc }' <<<"$1"
}

# --- Tests ---

test_every_object_labelled() {
  local output kinds missing
  output=$(render "${COMMON[@]}")

  # yq keeps the last of duplicate keys, so check the text. A chart-owned key
  # from commonLabels is never rendered; a key only the operator manages
  # (job-name) is rendered on the chart's objects, but not passed to it.
  local manifests hits
  manifests=$(grep -v -e 'value: "{' <<<"$output" || true)
  hits=$(grep -c '"control-plane": "hijack"' <<<"$manifests" || true)
  assert_eq "Chart-owned key from commonLabels is not rendered" "0" "$hits"
  assert_eq "control-plane kept on the Deployment, pod, Service and ServiceMonitor" "controller-manager controller-manager controller-manager controller-manager" \
    "$(yq -N -r 'select(.kind == "Deployment" or .kind == "Service" or .kind == "ServiceMonitor") | [.metadata.labels["control-plane"], .spec.template.metadata.labels["control-plane"] // ""] | join(" ")' <<<"$output" | xargs)"
  assert_eq "Operator-only key from commonLabels is rendered on every chart object" "" \
    "$(yq -N -r 'select(.kind != null) | select(.metadata.labels["job-name"] != "hijack") | .kind + "/" + .metadata.name' <<<"$output")"

  kinds=$(yq -N -r 'select(.kind != null) | .kind' <<<"$output" | sort | uniq -c | tr -s ' ' | tr '\n' ',')
  echo "  Rendered: $kinds"

  missing=$(yq -N -r 'select(.kind != null) | select(.metadata.labels.team != "remitly" or .metadata.labels["cost-center"] != "1234") | .kind + "/" + .metadata.name' <<<"$output")
  assert_eq "commonLabels on every object" "" "$missing"

  missing=$(yq -N -r 'select(.kind != null) | select(.metadata.annotations.note != "hello") | .kind + "/" + .metadata.name' <<<"$output")
  assert_eq "commonAnnotations on every object" "" "$missing"

  missing=$(yq -N -r 'select(.kind != null) | select(.metadata.annotations["helm.sh/resource-policy"] != null) | .kind + "/" + .metadata.name' <<<"$output")
  assert_eq "helm.sh/ annotations from commonAnnotations are dropped" "" "$missing"

  assert_eq "CRDs rendered" "3" "$(yq -N -r 'select(.kind == "CustomResourceDefinition") | .metadata.name' <<<"$output" | wc -l | tr -d ' ')"

  assert_eq "Pod template label" "remitly" \
    "$(yq -N -r 'select(.kind == "Deployment") | .spec.template.metadata.labels.team' <<<"$output")"
  assert_eq "Pod template annotation" "hello" \
    "$(yq -N -r 'select(.kind == "Deployment") | .spec.template.metadata.annotations.note' <<<"$output")"
  assert_eq "control-plane is not overridden" "controller-manager" \
    "$(yq -N -r 'select(.kind == "Deployment") | .spec.template.metadata.labels["control-plane"]' <<<"$output")"
  assert_eq "Selector unchanged" '{"app.kubernetes.io/instance":"test","app.kubernetes.io/name":"jupiterone-integration-operator","control-plane":"controller-manager"}' \
    "$(yq -N -o=json -I=0 'select(.kind == "Deployment") | .spec.selector.matchLabels | sort_keys(.)' <<<"$output")"
  assert_eq "Metrics certificate Secret label" "remitly" \
    "$(yq -N -r 'select(.kind == "Certificate") | .spec.secretTemplate.labels.team' <<<"$output")"
  assert_eq "Metrics certificate Secret annotation" "hello" \
    "$(yq -N -r 'select(.kind == "Certificate") | .spec.secretTemplate.annotations.note' <<<"$output")"
}

test_runtime_values() {
  local output jo cl
  output=$(render "${COMMON[@]}" \
    --set controllerManager.job.labels.team=job \
    --set controllerManager.job.podAnnotations.note=pod)
  jo=$(manager_env "$output" JOB_OVERRIDES)
  cl=$(manager_env "$output" COMMON_LABELS)

  assert_eq "JOB_OVERRIDES labels: job.labels win over commonLabels" \
    '{"cost-center":"1234","team":"job"}' "$(yq -o=json -I=0 '.labels' <<<"$jo")"
  assert_eq "JOB_OVERRIDES podLabels from commonLabels, chart and operator keys left out" \
    '{"cost-center":"1234","team":"remitly"}' "$(yq -o=json -I=0 '.podLabels' <<<"$jo")"
  assert_eq "JOB_OVERRIDES annotations from commonAnnotations, helm.sh/ left out" \
    '{"note":"hello"}' "$(yq -o=json -I=0 '.annotations' <<<"$jo")"
  assert_eq "JOB_OVERRIDES podAnnotations: job.podAnnotations win" \
    '{"note":"pod"}' "$(yq -o=json -I=0 '.podAnnotations' <<<"$jo")"
  assert_eq "COMMON_LABELS for the Lease, chart keys left out" '{"cost-center":"1234","job-name":"hijack","team":"remitly"}' \
    "$(yq -o=json -I=0 'sort_keys(.)' <<<"$cl")"
}

test_specific_values_win() {
  local output
  output=$(render "${COMMON[@]}" \
    --set controllerManager.pod.labels.team=pod \
    --set controllerManager.deployment.annotations.note=deployment \
    --set 'controllerManager.serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::123456789012:role/op' \
    --set 'integration.serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::123456789012:role/k8s' \
    --set 'integration.jobServiceAccount.annotations.note=sa')

  assert_eq "One team label each on the Deployment and its pod (no duplicate key)" "2" \
    "$(deployment_doc "$output" | grep -c '"team":')"
  assert_eq "pod.labels win on the pod" "pod" \
    "$(yq -N -r 'select(.kind == "Deployment") | .spec.template.metadata.labels.team' <<<"$output")"
  assert_eq "commonLabels still on the Deployment" "remitly" \
    "$(yq -N -r 'select(.kind == "Deployment") | .metadata.labels.team' <<<"$output")"
  assert_eq "deployment.annotations win on the Deployment" "deployment" \
    "$(yq -N -r 'select(.kind == "Deployment") | .metadata.annotations.note' <<<"$output")"
  assert_eq "IRSA and commonAnnotations on the operator ServiceAccount" "arn:aws:iam::123456789012:role/op hello" \
    "$(yq -N -r 'select(.kind == "ServiceAccount" and .metadata.name == "jupiterone-integration-operator-controller-manager") | .metadata.annotations["eks.amazonaws.com/role-arn"] + " " + .metadata.annotations.note' <<<"$output")"
  assert_eq "IRSA and commonAnnotations on the kubernetes-managed ServiceAccount" "arn:aws:iam::123456789012:role/k8s hello" \
    "$(yq -N -r 'select(.kind == "ServiceAccount" and .metadata.name == "jupiterone") | .metadata.annotations["eks.amazonaws.com/role-arn"] + " " + .metadata.annotations.note' <<<"$output")"
  assert_eq "Specific annotations win on the job ServiceAccount" "sa" \
    "$(yq -N -r 'select(.kind == "ServiceAccount" and .metadata.name == "jupiterone-integration-job") | .metadata.annotations.note' <<<"$output")"
}

test_crd_keep_with_common_annotations() {
  local output
  output=$(render --set crd.keep=true --set commonAnnotations.note=hello)
  assert_eq "CRDs keep helm.sh/resource-policy and get commonAnnotations" "keep hello keep hello keep hello" \
    "$(yq -N -r 'select(.kind == "CustomResourceDefinition") | .metadata.annotations["helm.sh/resource-policy"] + " " + .metadata.annotations.note' <<<"$output" | tr '\n' ' ' | sed 's/ $//')"
  assert_eq "CRDs keep the controller-gen annotation" "3" \
    "$(yq -N -r 'select(.kind == "CustomResourceDefinition") | .metadata.annotations["controller-gen.kubebuilder.io/version"]' <<<"$output" | grep -c .)"
}

test_defaults_add_nothing() {
  local output
  output=$(render)
  assert_eq "No COMMON_LABELS by default" "" "$(manager_env "$output" COMMON_LABELS)"
  assert_eq "No JOB_OVERRIDES by default" "" "$(manager_env "$output" JOB_OVERRIDES)"
  assert_eq "No secretTemplate by default" "null" \
    "$(yq -N -r 'select(.kind == "Certificate") | .spec.secretTemplate' <<<"$output")"
}

test_values_from_older_chart() {
  # helm upgrade --reuse-values from chart 1.5.0 has no commonLabels or
  # commonAnnotations.
  local output status=0
  output=$(render --set commonLabels=null --set commonAnnotations=null 2>&1) || status=$?
  if [ "$status" -eq 0 ]; then
    pass "Renders without commonLabels and commonAnnotations"
  else
    fail "Renders without commonLabels and commonAnnotations" "$output"
  fi
}

test_empty_and_false_specific_values_win() {
  # A blank or false specific value is still a value: it must not fall back to
  # commonLabels.
  local values output
  values=$(mktemp)
  cat >"$values" <<'YAML'
commonLabels:
  team: common
  flag: "yes"
  novalue: common
commonAnnotations:
  sidecar.istio.io/inject: "true"
controllerManager:
  pod:
    labels:
      team: ""
      flag: false
      novalue:
    annotations:
      sidecar.istio.io/inject: false
YAML
  output=$(render -f "$values")
  rm -f "$values"

  assert_eq "Pod: blank, false and no-value labels win over commonLabels" '{"flag":"false","novalue":"","team":""}' \
    "$(yq -o=json -I=0 'select(.kind == "Deployment") | .spec.template.metadata.labels | with_entries(select(.key == "team" or .key == "flag" or .key == "novalue")) | sort_keys(.)' <<<"$output")"
  assert_eq "Pod: false annotation wins over commonAnnotations" "false" \
    "$(yq -N -r 'select(.kind == "Deployment") | .spec.template.metadata.annotations["sidecar.istio.io/inject"]' <<<"$output")"
  assert_eq "Deployment keeps the common values" "common yes" \
    "$(yq -N -r 'select(.kind == "Deployment") | .metadata.labels.team + " " + .metadata.labels.flag' <<<"$output")"
}

# --- Run all tests ---

run_test "Every object labelled" test_every_object_labelled
run_test "Runtime values" test_runtime_values
run_test "Specific values win" test_specific_values_win
run_test "Blank and false specific values win" test_empty_and_false_specific_values_win
run_test "crd.keep with commonAnnotations" test_crd_keep_with_common_annotations
run_test "Defaults add nothing" test_defaults_add_nothing
run_test "Values from an older chart (--reuse-values)" test_values_from_older_chart

# --- Summary ---

echo ""
echo "=============================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=============================="
[ "$FAILED" -eq 0 ] || exit 1
