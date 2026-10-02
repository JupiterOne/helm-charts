package main

import (
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
	values, err := generateValuesYaml(k8sDefinitionWithConfig())
	if err != nil {
		t.Fatal(err)
	}
	edited := strings.Replace(values, "\npodLabels: {}\n", "\npodLabels:\n  empty:\n", 1)
	if edited == values {
		t.Fatal("values.yaml has no podLabels: {} line")
	}
	out := renderChartWithValues(t, k8sDefinitionWithConfig(), edited)
	if !strings.Contains(out, "\n    podLabels:\n      \"empty\": \"\"\n") || strings.Contains(out, "<nil>") {
		t.Errorf("want a key with no value rendered as \"\", got:\n%s", out)
	}
}
