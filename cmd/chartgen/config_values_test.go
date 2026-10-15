package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// configDefinition is k8sDefinition with one config field of each type that
// is not a plain string.
func configDefinition() IntegrationDefinition {
	def := k8sDefinition()
	def.ConfigFields = []ConfigField{
		{Key: "ingestAllNodeImages", Type: "boolean"},
		{Key: "includeNamespaces", Type: "array"},
		{Key: "crdMappingConfig", Type: "textFileUpload", Format: "yaml"},
	}
	return def
}

func TestRenderChart_QuotesEveryConfigValue(t *testing.T) {
	// spec.config only takes strings, so booleans, lists given as one string
	// and multi-line file contents must all render as quoted strings.
	mapping := filepath.Join(t.TempDir(), "mapping.yaml")
	if err := os.WriteFile(mapping, []byte("resources:\n  - name: \"a.example.com\"\n    _type: kube_cr_a\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	out := renderChart(t, configDefinition(),
		"--set", "ingestAllNodeImages=true",
		"--set", `includeNamespaces=["default"\,"prod"]`,
		"--set-file", "crdMappingConfig="+mapping)

	for _, want := range []string{
		"\n    ingestAllNodeImages: \"true\"\n",
		"\n    includeNamespaces: \"[\\\"default\\\",\\\"prod\\\"]\"\n",
		"\n    crdMappingConfig: \"resources:\\n  - name: \\\"a.example.com\\\"\\n    _type: kube_cr_a\\n\"\n",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("want %q in:\n%s", want, out)
		}
	}
}

func TestRenderChart_UnsetConfigValuesAreOmitted(t *testing.T) {
	out := renderChart(t, configDefinition(), "--set", "ingestAllNodeImages=false")
	if !strings.Contains(out, "\n  config:\n    {}\n") {
		t.Errorf("want an empty config, got:\n%s", out)
	}
}

func TestRenderChart_RejectsListOrMapConfigValue(t *testing.T) {
	// Helm would print a list as "[a b]", which no integration can read.
	values, err := generateValuesYaml(configDefinition())
	if err != nil {
		t.Fatal(err)
	}
	for _, arg := range []string{"includeNamespaces={default,prod}", "includeNamespaces.a=b"} {
		out, err := helmTemplate(t, configDefinition(), values, "--set", arg)
		if err == nil || !strings.Contains(out, "includeNamespaces must be a string") {
			t.Errorf("%s: want a render error naming includeNamespaces, got err=%v:\n%s", arg, err, out)
		}
	}
}
