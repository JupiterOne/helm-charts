package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestValuesYaml_DeclaresJobMetadata(t *testing.T) {
	values, err := generateValuesYaml(k8sDefinitionWithConfig())
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"\njobLabels: {}\n", "\njobAnnotations: {}\n", "\npodLabels: {}\n", "\npodAnnotations: {}\n",
		"jupiterone-integration-operator\n# " + minOperatorVersionForJobMetadata + " or later",
	} {
		if !strings.Contains(values, want) {
			t.Errorf("values.yaml missing %q", want)
		}
	}
}

func TestIntegrationInstanceTemplate_OmitsEmptyJobMetadata(t *testing.T) {
	out := renderChart(t, k8sDefinitionWithConfig())
	if strings.Contains(out, "\n  job:") {
		t.Errorf("empty job metadata should not render:\n%s", out)
	}
}

func TestIntegrationInstanceTemplate_RendersJobMetadata(t *testing.T) {
	// Values from a file, as users set them: an unquoted number and keys with
	// a prefix must come out as quoted strings.
	values, err := generateValuesYaml(k8sDefinitionWithConfig())
	if err != nil {
		t.Fatal(err)
	}
	// Replace one at a time: the entries are adjacent lines, so a single
	// strings.Replacer would consume the newline the next match starts with.
	edited := values
	for _, r := range [][2]string{
		{"jobLabels: {}\n", "jobLabels:\n  team: security\n"},
		{"podLabels: {}\n", "podLabels:\n  cost-center: 1234\n"},
		{"podAnnotations: {}\n", "podAnnotations:\n  sidecar.istio.io/inject: \"false\"\n"},
	} {
		if !strings.Contains(edited, "\n"+r[0]) {
			t.Fatalf("values.yaml has no %q line", r[0])
		}
		edited = strings.Replace(edited, "\n"+r[0], "\n"+r[1], 1)
	}
	out := renderChartWithValues(t, k8sDefinitionWithConfig(), edited, "--set", "clusterName=prod")

	instance := out[strings.Index(out, "kind: IntegrationInstance"):]
	for _, want := range []string{
		"\n  job:\n    labels:\n      \"team\": \"security\"\n    podAnnotations:\n      \"sidecar.istio.io/inject\": \"false\"\n    podLabels:\n      \"cost-center\": \"1234\"\n",
		"\n  config:\n    clusterName: \"prod\"",
	} {
		if !strings.Contains(instance, want) {
			t.Errorf("IntegrationInstance missing %q:\n%s", want, instance)
		}
	}
	if strings.Contains(instance, "\n    annotations:") {
		t.Errorf("empty jobAnnotations should not render:\n%s", instance)
	}
}

func TestIntegrationInstanceTemplate_JobMetadataEmptyValue(t *testing.T) {
	// A key with no value in a user values file must not render as "<nil>".
	// Helm 3 passes it through as null (rendered ""); Helm 4 may drop it.
	userValues := filepath.Join(t.TempDir(), "user.yaml")
	if err := os.WriteFile(userValues, []byte("podLabels:\n  empty:\n  team: security\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	out := renderChart(t, k8sDefinitionWithConfig(), "-f", userValues)
	if strings.Contains(out, "<nil>") {
		t.Errorf("a key with no value rendered as <nil>:\n%s", out)
	}
	if !strings.Contains(out, "\n    podLabels:\n") || !strings.Contains(out, "\"team\": \"security\"") {
		t.Errorf("want podLabels with team rendered, got:\n%s", out)
	}
	if strings.Contains(out, "\"empty\":") && !strings.Contains(out, "\"empty\": \"\"") {
		t.Errorf("want a key with no value rendered as \"\" when kept, got:\n%s", out)
	}
}

func TestValuesYaml_DeclaresCommonMetadata(t *testing.T) {
	values, err := generateValuesYaml(k8sDefinitionWithConfig())
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"\ncommonLabels: {}\n", "\ncommonAnnotations: {}\n"} {
		if !strings.Contains(values, want) {
			t.Errorf("values.yaml missing %q", want)
		}
	}
}

func TestChart_CommonMetadataOnEveryObject(t *testing.T) {
	userValues := filepath.Join(t.TempDir(), "user.yaml")
	if err := os.WriteFile(userValues, []byte(`commonLabels:
  team: remitly
  cost-center: "1234"
  job-name: hijack
commonAnnotations:
  note: hello
  helm.sh/resource-policy: keep
podLabels:
  team: pod
jobAnnotations:
  note: job
`), 0o644); err != nil {
		t.Fatal(err)
	}
	out := renderChart(t, k8sDefinitionWithConfig(), "-f", userValues, "--set", "secret.apiToken=x")

	secret := out[strings.Index(out, "kind: Secret"):]
	secret = secret[:strings.Index(secret, "\n---")]
	instance := out[strings.Index(out, "kind: IntegrationInstance"):]

	metadata := "\n  labels:\n    \"cost-center\": \"1234\"\n    \"job-name\": \"hijack\"\n    \"team\": \"remitly\"\n  annotations:\n    \"note\": \"hello\"\n"
	if !strings.Contains(secret, metadata) {
		t.Errorf("Secret missing common metadata %q:\n%s", metadata, secret)
	}
	if !strings.Contains(instance, metadata) {
		t.Errorf("IntegrationInstance missing common metadata %q:\n%s", metadata, instance)
	}
	job := "\n  job:\n" +
		"    annotations:\n      \"note\": \"job\"\n" +
		"    labels:\n      \"cost-center\": \"1234\"\n      \"team\": \"remitly\"\n" +
		"    podAnnotations:\n      \"note\": \"hello\"\n" +
		"    podLabels:\n      \"cost-center\": \"1234\"\n      \"team\": \"pod\"\n"
	if !strings.Contains(instance, job) {
		t.Errorf("IntegrationInstance missing spec.job %q:\n%s", job, instance)
	}
	if strings.Contains(out, "resource-policy") {
		t.Errorf("helm.sh/ annotations from commonAnnotations must be dropped:\n%s", out)
	}
	if strings.Count(instance, "hijack") != 1 {
		t.Errorf("a key the operator manages must stay out of spec.job:\n%s", instance)
	}
}

func TestChart_CommonMetadataUnsetOrNull(t *testing.T) {
	for name, args := range map[string][]string{
		"defaults": nil,
		// helm upgrade --reuse-values from a chart without these values.
		"null": {"--set", "commonLabels=null", "--set", "commonAnnotations=null", "--set", "jobLabels=null", "--set", "podLabels=null"},
	} {
		t.Run(name, func(t *testing.T) {
			out := renderChart(t, k8sDefinitionWithConfig(), append([]string{"--set", "secret.apiToken=x"}, args...)...)
			for _, unwanted := range []string{"labels:", "annotations:", "\n  job:"} {
				if strings.Contains(out, unwanted) {
					t.Errorf("unexpected %q:\n%s", unwanted, out)
				}
			}
		})
	}
}

func TestChart_BlankAndFalseJobValuesWinOverCommon(t *testing.T) {
	// A blank or false value is still a value: it must not fall back to the
	// common one.
	userValues := filepath.Join(t.TempDir(), "user.yaml")
	if err := os.WriteFile(userValues, []byte(`commonLabels:
  shared: common
  flag: "yes"
commonAnnotations:
  sidecar.istio.io/inject: "true"
podLabels:
  shared: ""
  flag: false
podAnnotations:
  sidecar.istio.io/inject: false
`), 0o644); err != nil {
		t.Fatal(err)
	}
	instance := renderChart(t, k8sDefinitionWithConfig(), "-f", userValues)
	instance = instance[strings.Index(instance, "kind: IntegrationInstance"):]
	for _, want := range []string{
		"    podAnnotations:\n      \"sidecar.istio.io/inject\": \"false\"\n",
		"    podLabels:\n      \"flag\": \"false\"\n      \"shared\": \"\"\n",
		"    labels:\n      \"flag\": \"yes\"\n      \"shared\": \"common\"\n",
	} {
		if !strings.Contains(instance, want) {
			t.Errorf("IntegrationInstance missing %q:\n%s", want, instance)
		}
	}
}
