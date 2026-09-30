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
		"# replace {} with the entries you need",
		"# Keep this in a values file (-f).",
		"#   ingestionSources:\n#     secrets: false\n",
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
	values, err := generateValuesYaml(def)
	if err != nil {
		t.Fatal(err)
	}
	return renderChartWithValues(t, def, values, args...)
}

// renderChartWithValues is renderChart with the chart's values.yaml given.
func renderChartWithValues(t *testing.T, def IntegrationDefinition, values string, args ...string) string {
	t.Helper()
	if _, err := exec.LookPath("helm"); err != nil {
		t.Skip("helm not installed")
	}
	dir := t.TempDir()
	instance, err := generateIntegrationInstanceYaml(def)
	if err != nil {
		t.Fatal(err)
	}
	files := map[string]string{
		"Chart.yaml":                         "apiVersion: v2\nname: test\nversion: 0.0.1\n",
		"values.yaml":                        values,
		"templates/integrationinstance.yaml": instance,
	}
	if hasSecretFields(def) {
		secret, err := generateSecretYaml(def)
		if err != nil {
			t.Fatal(err)
		}
		files["templates/secret.yaml"] = secret
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

// k8sDefinitionWithConfig is k8sDefinition plus a plain and a masked config
// field, so the chart renders spec.config, spec.secretRef and a Secret
// alongside ingestionSources.
func k8sDefinitionWithConfig() IntegrationDefinition {
	def := k8sDefinition()
	def.ConfigFields = []ConfigField{
		{Key: "clusterName", Type: "string", Description: "Cluster name"},
		{Key: "apiToken", Type: "string", Description: "API token", Mask: true},
	}
	return def
}

func TestRenderChart_SourcesWithConfigAndSecret(t *testing.T) {
	def := k8sDefinitionWithConfig()
	if !hasSecretFields(def) {
		t.Fatal("definition must have secret fields")
	}
	out := renderChart(t, def,
		"--set", "ingestionSources.secrets=false",
		"--set", "clusterName=prod",
		"--set", "secret.apiToken=s3cr3t")

	// helm template parses every rendered manifest, so reaching here means the
	// output is valid YAML. Check ingestionSources sits in the spec mapping,
	// alongside secretRef and config, not after it.
	instance := out[strings.Index(out, "kind: IntegrationInstance"):]
	for _, want := range []string{
		"\nspec:\n",
		"\n  ingestionSources:\n    secrets: false\n  secretRef: ",
		"\n  config:\n    clusterName: \"prod\"",
	} {
		if !strings.Contains(instance, want) {
			t.Errorf("IntegrationInstance missing %q:\n%s", want, instance)
		}
	}
	if !strings.Contains(out, "kind: Secret") || !strings.Contains(out, `apiToken: "s3cr3t"`) {
		t.Errorf("want the Secret with apiToken, got:\n%s", out)
	}
}

func TestRenderChart_EditedValuesParse(t *testing.T) {
	// Editing values.yaml as its comment says (replace {} with the entries)
	// must leave a file helm parses, with the source list still commented out.
	def := k8sDefinitionWithConfig()
	values, err := generateValuesYaml(def)
	if err != nil {
		t.Fatal(err)
	}
	edited := strings.Replace(values, "ingestionSources: {}\n", "ingestionSources:\n  secrets: false\n", 1)
	if edited == values {
		t.Fatal("values.yaml has no ingestionSources: {} line")
	}
	out := renderChartWithValues(t, def, edited)
	if !strings.Contains(out, "\n  ingestionSources:\n    secrets: false\n") {
		t.Errorf("want ingestionSources from the edited values.yaml, got:\n%s", out)
	}
}
