package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func k8sDefinition() IntegrationDefinition {
	return IntegrationDefinition{
		Name: "kubernetes-managed",
		IntegrationPlatformFeatures: IntegrationPlatformFeatures{
			SupportsCollectors:             true,
			SupportsIngestionSourcesConfig: true,
		},
		IngestionSourcesConfig: []IngestionSourceConfig{
			{ID: "secrets", Title: "Secrets"},
			{ID: "container-specs", Title: "Container Specs", DefaultsToDisabled: true},
			{ID: "clusters", Title: "Clusters", CannotBeDisabled: true},
		},
	}
}

func TestGetIngestionSources(t *testing.T) {
	got := getIngestionSources(k8sDefinition())
	ids := []string{}
	for _, s := range got {
		ids = append(ids, s.ID)
	}
	if strings.Join(ids, ",") != "clusters,container-specs,secrets" {
		t.Fatalf("want sorted ids, got %v", ids)
	}

	def := k8sDefinition()
	def.IntegrationPlatformFeatures.SupportsIngestionSourcesConfig = false
	if getIngestionSources(def) != nil {
		t.Fatal("want nil when the definition does not support ingestion sources")
	}
}

func TestValuesYaml_ListsIngestionSources(t *testing.T) {
	out, err := generateValuesYaml(k8sDefinition())
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"ingestionSources: {}",
		"#   clusters: true  # Clusters (cannot be disabled)",
		"#   container-specs: false  # Container Specs",
		"#   secrets: true  # Secrets",
		"v0.5.0",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("values.yaml missing %q:\n%s", want, out)
		}
	}
}

func TestValuesYaml_OmitsIngestionSourcesWhenUnsupported(t *testing.T) {
	def := k8sDefinition()
	def.IntegrationPlatformFeatures.SupportsIngestionSourcesConfig = false
	out, err := generateValuesYaml(def)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(out, "ingestionSources") {
		t.Errorf("values.yaml should not mention ingestionSources:\n%s", out)
	}
}

// renderChart writes a minimal chart from the generated templates and runs
// `helm template` with args, returning the rendered manifest.
func renderChart(t *testing.T, def IntegrationDefinition, args ...string) string {
	t.Helper()
	if _, err := exec.LookPath("helm"); err != nil {
		t.Skip("helm not installed")
	}
	dir := t.TempDir()
	values, err := generateValuesYaml(def)
	if err != nil {
		t.Fatal(err)
	}
	instance, err := generateIntegrationInstanceYaml(def)
	if err != nil {
		t.Fatal(err)
	}
	files := map[string]string{
		"Chart.yaml":                         "apiVersion: v2\nname: test\nversion: 0.0.1\n",
		"values.yaml":                        values,
		"templates/integrationinstance.yaml": instance,
	}
	for name, content := range files {
		path := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	out, err := exec.Command("helm", append([]string{"template", "t", dir}, args...)...).CombinedOutput()
	if err != nil {
		t.Fatalf("helm template: %v\n%s", err, out)
	}
	return string(out)
}

func TestIntegrationInstanceTemplate_RendersBooleanSources(t *testing.T) {
	out := renderChart(t, k8sDefinition(), "--set", "ingestionSources.secrets=false", "--set", "ingestionSources.container-specs=true")
	if !strings.Contains(out, "  ingestionSources:\n    container-specs: true\n    secrets: false\n") {
		t.Errorf("want boolean ingestionSources block, got:\n%s", out)
	}
}

func TestIntegrationInstanceTemplate_OmitsEmptySources(t *testing.T) {
	out := renderChart(t, k8sDefinition())
	if strings.Contains(out, "ingestionSources") {
		t.Errorf("empty ingestionSources should not render:\n%s", out)
	}
}
