package main

import (
	"bufio"
	"bytes"
	"embed"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"text/template"

	"github.com/Masterminds/semver/v3"
	"github.com/spf13/cobra"
)

//go:embed templates/*.tmpl
var templateFS embed.FS

const (
	// Default GraphQL endpoint for fetching integration definitions
	defaultGraphQLEndpoint = "https://graphql.us.jupiterone.io"
)

// getGraphQLEndpoint returns the GraphQL endpoint, checking for environment variable override
func getGraphQLEndpoint() string {
	if endpoint := os.Getenv("J1_GRAPHQL_ENDPOINT"); endpoint != "" {
		return endpoint
	}
	return defaultGraphQLEndpoint
}

// GraphQL types
type GraphQLRequest struct {
	Query     string         `json:"query"`
	Variables map[string]any `json:"variables,omitempty"`
}

type GraphQLResponse struct {
	Data   IntegrationDefinitionsData `json:"data"`
	Errors []GraphQLError             `json:"errors,omitempty"`
}

type GraphQLError struct {
	Message string `json:"message"`
}

type IntegrationDefinitionsData struct {
	IntegrationDefinitions IntegrationDefinitions `json:"integrationDefinitions"`
}

type IntegrationDefinitions struct {
	Definitions []IntegrationDefinition `json:"definitions"`
	PageInfo    PageInfo                `json:"pageInfo"`
}

type IntegrationDefinition struct {
	ID                          string                      `json:"id"`
	Name                        string                      `json:"name"`
	IntegrationType             string                      `json:"integrationType"`
	Title                       string                      `json:"title"`
	IntegrationPlatformFeatures IntegrationPlatformFeatures `json:"integrationPlatformFeatures"`
	ConfigFields                []ConfigField               `json:"configFields"`
	ConfigSections              []ConfigSection             `json:"configSections"`
	AuthSections                []AuthSection               `json:"authSections"`
}

type IntegrationPlatformFeatures struct {
	SupportsCollectors bool     `json:"supportsCollectors"`
	ExecutionTarget    []string `json:"executionTarget"`
}

type ConfigField struct {
	Key          string         `json:"key"`
	DisplayName  string         `json:"displayName"`
	Description  string         `json:"description"`
	Type         string         `json:"type"`
	Format       string         `json:"format"`
	Options      []ConfigOption `json:"options"`
	DefaultValue any            `json:"defaultValue"`
	HelperText   string         `json:"helperText"`
	Mask         bool           `json:"mask"`
	Optional     bool           `json:"optional"`
	ConfigFields []ConfigField  `json:"configFields"` // Nested config fields
}

type ConfigOption struct {
	Label string `json:"label"`
	Value string `json:"value"`
}

type ConfigSection struct {
	DisplayName  string        `json:"displayName"`
	ConfigFields []ConfigField `json:"configFields"`
}

type AuthSection struct {
	ID                   string        `json:"id"`
	DisplayName          string        `json:"displayName"`
	Description          string        `json:"description"`
	ConfigFields         []ConfigField `json:"configFields"`
	VerificationDisabled bool          `json:"verificationDisabled"`
}

type PageInfo struct {
	EndCursor   string `json:"endCursor"`
	HasNextPage bool   `json:"hasNextPage"`
}

var (
	apiKey          string
	accountID       string
	outputDir       string
	integrationName string
	write           bool
	verbose         bool
	rootCmd         = &cobra.Command{
		Use:   "chartgen",
		Short: "Generate Helm charts for JupiterOne integrations that support collectors",
		Long: `chartgen fetches integration definitions from the JupiterOne GraphQL API
and generates Helm charts for each integration that supports collectors.

The generated charts create IntegrationInstance custom resources that can be
deployed alongside the jupiterone-integration-operator.`,
		RunE: runChartGen,
	}
)

func init() {
	rootCmd.Flags().StringVarP(&apiKey, "api-key", "k", "", "JupiterOne API key (required)")
	rootCmd.Flags().StringVarP(&accountID, "account-id", "a", "", "JupiterOne account ID (required)")
	rootCmd.Flags().StringVarP(&outputDir, "output", "o", "./charts", "Output directory for generated charts")
	rootCmd.Flags().StringVarP(&integrationName, "name", "n", "", "Generate chart for a specific integration by name")
	rootCmd.Flags().BoolVarP(&write, "write", "w", false, "Write files to disk (default is dry-run mode)")
	rootCmd.Flags().BoolVarP(&verbose, "verbose", "v", false, "Enable verbose output")
	rootCmd.MarkFlagRequired("api-key")
	rootCmd.MarkFlagRequired("account-id")
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func runChartGen(cmd *cobra.Command, args []string) error {
	// If a specific integration name is provided, fetch and generate only that one
	if integrationName != "" {
		def, err := fetchIntegrationByName(integrationName)
		if err != nil {
			return fmt.Errorf("failed to fetch integration %s: %w", integrationName, err)
		}

		if def == nil {
			return fmt.Errorf("integration %s not found", integrationName)
		}

		err, changed := generateChart(*def)
		if err != nil {
			return fmt.Errorf("failed to generate chart for %s: %w", integrationName, err)
		}

		if changed {
			fmt.Printf("Successfully generated chart for %s\n", integrationName)
		} else {
			fmt.Printf("No changes for %s\n", integrationName)
		}
		return nil
	}

	// Fetch all integration definitions
	definitions, err := fetchAllIntegrationDefinitions()
	if err != nil {
		return fmt.Errorf("failed to fetch integration definitions: %w", err)
	}

	if verbose {
		fmt.Printf("Fetched %d total integration definitions\n", len(definitions))
	}

	// Filter for collector-supported integrations
	collectorSupported := filterCollectorSupported(definitions)

	if verbose {
		fmt.Printf("Found %d integrations that support collectors\n", len(collectorSupported))
	}

	if len(collectorSupported) == 0 {
		fmt.Println("No integrations found that support collectors")
		return nil
	}

	// Generate charts
	updated := 0
	for _, def := range collectorSupported {
		err, changed := generateChart(def)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Warning: failed to generate chart for %s: %v\n", def.Name, err)
			continue
		}
		if changed {
			updated++
		}
	}

	fmt.Printf("Updated %d of %d charts\n", updated, len(collectorSupported))
	return nil
}

func fetchAllIntegrationDefinitions() ([]IntegrationDefinition, error) {
	var allDefinitions []IntegrationDefinition
	var cursor *string

	// Fragment for config field properties (used to avoid repetition)
	// Note: GraphQL doesn't support infinite recursion, so we go 2 levels deep for nested configFields
	query := `query GetCollectorSupportedIntegrations($cursor: String) {
    integrationDefinitions(cursor: $cursor) {
      definitions {
        id
        name
        integrationType
        title
        integrationPlatformFeatures {
          supportsCollectors
          executionTarget
        }
        configFields {
          key
          displayName
          description
          type
          format
          options {
            label
            value
          }
          defaultValue
          helperText
          mask
          optional
          configFields {
            key
            displayName
            description
            type
            format
            options {
              label
              value
            }
            defaultValue
            helperText
            mask
            optional
            configFields {
              key
              displayName
              description
              type
              format
              options {
                label
                value
              }
              defaultValue
              helperText
              mask
              optional
            }
          }
        }
        configSections {
          displayName
          configFields {
            key
            displayName
            description
            type
            format
            options {
              label
              value
            }
            defaultValue
            helperText
            mask
            optional
            configFields {
              key
              displayName
              description
              type
              format
              options {
                label
                value
              }
              defaultValue
              helperText
              mask
              optional
              configFields {
                key
                displayName
                description
                type
                format
                options {
                  label
                  value
                }
                defaultValue
                helperText
                mask
                optional
              }
            }
          }
        }
        authSections {
          id
          displayName
          description
          verificationDisabled
          configFields {
            key
            displayName
            description
            type
            format
            options {
              label
              value
            }
            defaultValue
            helperText
            mask
            optional
            configFields {
              key
              displayName
              description
              type
              format
              options {
                label
                value
              }
              defaultValue
              helperText
              mask
              optional
              configFields {
                key
                displayName
                description
                type
                format
                options {
                  label
                  value
                }
                defaultValue
                helperText
                mask
                optional
              }
            }
          }
        }
      }
      pageInfo {
        endCursor
        hasNextPage
      }
    }
  }`

	for {
		variables := make(map[string]any)
		if cursor != nil {
			variables["cursor"] = *cursor
		}

		reqBody := GraphQLRequest{
			Query:     query,
			Variables: variables,
		}

		jsonBody, err := json.Marshal(reqBody)
		if err != nil {
			return nil, fmt.Errorf("failed to marshal request: %w", err)
		}

		req, err := http.NewRequest("POST", getGraphQLEndpoint(), bytes.NewBuffer(jsonBody))
		if err != nil {
			return nil, fmt.Errorf("failed to create request: %w", err)
		}

		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", apiKey))
		req.Header.Set("JupiterOne-Account", accountID)

		client := &http.Client{}
		resp, err := client.Do(req)
		if err != nil {
			return nil, fmt.Errorf("failed to execute request: %w", err)
		}
		defer resp.Body.Close()

		body, err := io.ReadAll(resp.Body)
		if err != nil {
			return nil, fmt.Errorf("failed to read response: %w", err)
		}

		if resp.StatusCode != http.StatusOK {
			return nil, fmt.Errorf("unexpected status code %d: %s", resp.StatusCode, string(body))
		}

		var graphqlResp GraphQLResponse
		if err := json.Unmarshal(body, &graphqlResp); err != nil {
			return nil, fmt.Errorf("failed to unmarshal response: %w", err)
		}

		if len(graphqlResp.Errors) > 0 {
			return nil, fmt.Errorf("GraphQL errors: %v", graphqlResp.Errors)
		}

		allDefinitions = append(allDefinitions, graphqlResp.Data.IntegrationDefinitions.Definitions...)

		if !graphqlResp.Data.IntegrationDefinitions.PageInfo.HasNextPage {
			break
		}

		cursor = &graphqlResp.Data.IntegrationDefinitions.PageInfo.EndCursor
	}

	return allDefinitions, nil
}

func fetchIntegrationByName(name string) (*IntegrationDefinition, error) {
	// Note: GraphQL doesn't support infinite recursion, so we go 2 levels deep for nested configFields
	query := `query FindIntegrationDefinition($integrationType: String!) {
    findIntegrationDefinition(integrationType: $integrationType) {
      id
      name
      integrationType
      title
      integrationPlatformFeatures {
        supportsCollectors
        executionTarget
      }
      configFields {
        key
        displayName
        description
        type
        format
        options {
          label
          value
        }
        defaultValue
        helperText
        mask
        optional
        configFields {
          key
          displayName
          description
          type
          format
          options {
            label
            value
          }
          defaultValue
          helperText
          mask
          optional
          configFields {
            key
            displayName
            description
            type
            format
            options {
              label
              value
            }
            defaultValue
            helperText
            mask
            optional
          }
        }
      }
      configSections {
        displayName
        configFields {
          key
          displayName
          description
          type
          format
          options {
            label
            value
          }
          defaultValue
          helperText
          mask
          optional
          configFields {
            key
            displayName
            description
            type
            format
            options {
              label
              value
            }
            defaultValue
            helperText
            mask
            optional
            configFields {
              key
              displayName
              description
              type
              format
              options {
                label
                value
              }
              defaultValue
              helperText
              mask
              optional
            }
          }
        }
      }
      authSections {
        id
        displayName
        description
        verificationDisabled
        configFields {
          key
          displayName
          description
          type
          format
          options {
            label
            value
          }
          defaultValue
          helperText
          mask
          optional
          configFields {
            key
            displayName
            description
            type
            format
            options {
              label
              value
            }
            defaultValue
            helperText
            mask
            optional
            configFields {
              key
              displayName
              description
              type
              format
              options {
                label
                value
              }
              defaultValue
              helperText
              mask
              optional
            }
          }
        }
      }
    }
  }`

	variables := map[string]any{
		"integrationType": name,
	}

	reqBody := GraphQLRequest{
		Query:     query,
		Variables: variables,
	}

	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequest("POST", getGraphQLEndpoint(), bytes.NewBuffer(jsonBody))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", apiKey))
	req.Header.Set("JupiterOne-Account", accountID)

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to execute request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status code %d: %s", resp.StatusCode, string(body))
	}

	var graphqlResp struct {
		Data struct {
			FindIntegrationDefinition *IntegrationDefinition `json:"findIntegrationDefinition"`
		} `json:"data"`
		Errors []GraphQLError `json:"errors,omitempty"`
	}

	if err := json.Unmarshal(body, &graphqlResp); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(graphqlResp.Errors) > 0 {
		return nil, fmt.Errorf("GraphQL errors: %v", graphqlResp.Errors)
	}

	if graphqlResp.Data.FindIntegrationDefinition == nil {
		return nil, fmt.Errorf("integration %q not found", name)
	}

	return graphqlResp.Data.FindIntegrationDefinition, nil
}

func filterCollectorSupported(definitions []IntegrationDefinition) []IntegrationDefinition {
	var filtered []IntegrationDefinition
	for _, def := range definitions {
		if shouldGenerateChart(def) {
			filtered = append(filtered, def)
		}
	}
	return filtered
}

func shouldGenerateChart(def IntegrationDefinition) bool {
	if def.IntegrationPlatformFeatures.SupportsCollectors {
		return true
	}

	for _, target := range def.IntegrationPlatformFeatures.ExecutionTarget {
		if target == "KUBE_COLLECTOR" {
			return true
		}
	}

	return false
}

// flattenConfigFields recursively flattens nested config fields into a single slice
func flattenConfigFields(fields []ConfigField, seen map[string]bool) []ConfigField {
	var result []ConfigField
	for _, cf := range fields {
		if !seen[cf.Key] {
			seen[cf.Key] = true
			result = append(result, cf)
		}
		// Recursively add nested fields
		if len(cf.ConfigFields) > 0 {
			nested := flattenConfigFields(cf.ConfigFields, seen)
			result = append(result, nested...)
		}
	}
	return result
}

// getNonMaskedConfigFields returns all non-masked config fields (from configFields and configSections)
func getNonMaskedConfigFields(def IntegrationDefinition) []ConfigField {
	seen := make(map[string]bool)
	var fields []ConfigField

	// Flatten all configFields (including nested)
	allConfigFields := flattenConfigFields(def.ConfigFields, make(map[string]bool))

	// Add non-masked configFields
	for _, cf := range allConfigFields {
		if !seen[cf.Key] && !cf.Mask {
			seen[cf.Key] = true
			fields = append(fields, cf)
		}
	}

	// Flatten and add non-masked fields from configSections
	for _, cs := range def.ConfigSections {
		sectionFields := flattenConfigFields(cs.ConfigFields, make(map[string]bool))
		for _, cf := range sectionFields {
			if !seen[cf.Key] && !cf.Mask {
				seen[cf.Key] = true
				fields = append(fields, cf)
			}
		}
	}

	return fields
}

// getMaskedConfigFields returns all masked config fields (from configFields and configSections)
func getMaskedConfigFields(def IntegrationDefinition) []ConfigField {
	seen := make(map[string]bool)
	var fields []ConfigField

	// Flatten all configFields (including nested)
	allConfigFields := flattenConfigFields(def.ConfigFields, make(map[string]bool))

	// Add masked configFields
	for _, cf := range allConfigFields {
		if !seen[cf.Key] && cf.Mask {
			seen[cf.Key] = true
			fields = append(fields, cf)
		}
	}

	// Flatten and add masked fields from configSections
	for _, cs := range def.ConfigSections {
		sectionFields := flattenConfigFields(cs.ConfigFields, make(map[string]bool))
		for _, cf := range sectionFields {
			if !seen[cf.Key] && cf.Mask {
				seen[cf.Key] = true
				fields = append(fields, cf)
			}
		}
	}

	return fields
}

// getAllConfigFields returns all config fields (from configFields and configSections)
func getAllConfigFields(def IntegrationDefinition) []ConfigField {
	seen := make(map[string]bool)
	var fields []ConfigField

	// Flatten and add all configFields (including nested)
	allConfigFields := flattenConfigFields(def.ConfigFields, make(map[string]bool))
	for _, cf := range allConfigFields {
		if !seen[cf.Key] {
			seen[cf.Key] = true
			fields = append(fields, cf)
		}
	}

	// Flatten and add fields from configSections
	for _, cs := range def.ConfigSections {
		sectionFields := flattenConfigFields(cs.ConfigFields, make(map[string]bool))
		for _, cf := range sectionFields {
			if !seen[cf.Key] {
				seen[cf.Key] = true
				fields = append(fields, cf)
			}
		}
	}

	return fields
}

// getAllAuthFields returns all sensitive auth fields (from authSections), deduplicated
func getAllAuthFields(def IntegrationDefinition) []ConfigField {
	seen := make(map[string]bool)
	var fields []ConfigField

	for _, as := range def.AuthSections {
		// Flatten auth section fields (including nested)
		sectionFields := flattenConfigFields(as.ConfigFields, make(map[string]bool))
		for _, cf := range sectionFields {
			if !seen[cf.Key] {
				seen[cf.Key] = true
				fields = append(fields, cf)
			}
		}
	}

	return fields
}

// getFlattenedAuthSections returns auth sections with flattened configFields
func getFlattenedAuthSections(def IntegrationDefinition) []AuthSection {
	var result []AuthSection
	for _, as := range def.AuthSections {
		flattened := AuthSection{
			ID:                   as.ID,
			DisplayName:          as.DisplayName,
			Description:          as.Description,
			VerificationDisabled: as.VerificationDisabled,
			ConfigFields:         flattenConfigFields(as.ConfigFields, make(map[string]bool)),
		}
		result = append(result, flattened)
	}
	return result
}

// hasAuthFields returns true if the integration has any auth fields
func hasAuthFields(def IntegrationDefinition) bool {
	for _, as := range def.AuthSections {
		if len(as.ConfigFields) > 0 {
			return true
		}
	}
	return false
}

// hasSecretFields returns true if there are any masked config fields or auth fields
func hasSecretFields(def IntegrationDefinition) bool {
	return len(getMaskedConfigFields(def)) > 0 || hasAuthFields(def)
}

// readFileIfExists reads a file and returns its content, or empty string if it doesn't exist
func readFileIfExists(path string) string {
	content, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return string(content)
}

// chartContentChanged compares generated content with existing files (excluding Chart.yaml version line)
func chartContentChanged(chartDir string, files map[string]string) bool {
	for relPath, newContent := range files {
		fullPath := filepath.Join(chartDir, relPath)
		existingContent := readFileIfExists(fullPath)

		// For Chart.yaml, compare without the version line
		if relPath == "Chart.yaml" {
			existingNoVersion := removeVersionLine(existingContent)
			newNoVersion := removeVersionLine(newContent)
			if existingNoVersion != newNoVersion {
				return true
			}
		} else {
			if existingContent != newContent {
				return true
			}
		}
	}
	return false
}

// removeVersionLine removes the version: line from Chart.yaml content for comparison
func removeVersionLine(content string) string {
	var lines []string
	for _, line := range strings.Split(content, "\n") {
		if !strings.HasPrefix(line, "version:") {
			lines = append(lines, line)
		}
	}
	return strings.Join(lines, "\n")
}

// generateChart generates a Helm chart for the given integration definition.
// Returns (error, changed) where changed indicates if files were written.
func generateChart(def IntegrationDefinition) (error, bool) {
	chartName := def.Name

	// Validate chart name (must be valid Kubernetes name)
	chartName = sanitizeChartName(chartName)

	configFields := getAllConfigFields(def)
	authFields := getAllAuthFields(def)

	if verbose {
		fmt.Printf("Generating chart: %s (from %s)\n", chartName, def.Name)
	}

	if !write {
		fmt.Printf("[dry-run] Would generate chart: %s\n", chartName)
		fmt.Printf("  Title: %s\n", def.Title)
		fmt.Printf("  Config fields: %d\n", len(configFields))
		for _, cf := range configFields {
			optionalStr := ""
			if cf.Optional {
				optionalStr = " (optional)"
			}
			fmt.Printf("    - %s (%s)%s\n", cf.Key, cf.Type, optionalStr)
		}
		fmt.Printf("  Auth fields (secret): %d\n", len(authFields))
		for _, cf := range authFields {
			optionalStr := ""
			if cf.Optional {
				optionalStr = " (optional)"
			}
			fmt.Printf("    - %s (%s)%s\n", cf.Key, cf.Type, optionalStr)
		}
		return nil, false
	}

	chartDir := filepath.Join(outputDir, chartName)
	templatesDir := filepath.Join(chartDir, "templates")

	// Get current version (will be used for initial generation to compare)
	currentVersion := getCurrentChartVersion(chartName)

	// Generate all files with current version first (for comparison)
	files := make(map[string]string)

	// Generate Chart.yaml with current version
	chartYaml, err := generateChartYaml(def, currentVersion)
	if err != nil {
		return fmt.Errorf("failed to generate Chart.yaml: %w", err), false
	}
	files["Chart.yaml"] = chartYaml

	// Generate values.yaml
	valuesYaml, err := generateValuesYaml(def)
	if err != nil {
		return fmt.Errorf("failed to generate values.yaml: %w", err), false
	}
	files["values.yaml"] = valuesYaml

	// Generate .helmignore
	helmignore := `# Patterns to ignore when building Helm packages.
# Operating system files
.DS_Store

# Version control directories
.git/
.gitignore
.bzr/
.hg/
.hgignore
.svn/

# Backup and temporary files
*.swp
*.tmp
*.bak
*.orig
*~

# IDE and editor-related files
.idea/
.vscode/

# Helm chart artifacts
dist/chart/*.tgz
`
	files[".helmignore"] = helmignore

	// Generate integrationinstance.yaml template
	instanceYaml, err := generateIntegrationInstanceYaml(def)
	if err != nil {
		return fmt.Errorf("failed to generate integrationinstance.yaml: %w", err), false
	}
	files["templates/integrationinstance.yaml"] = instanceYaml

	// Generate secret.yaml template if there are secret fields
	if hasSecretFields(def) {
		secretYaml, err := generateSecretYaml(def)
		if err != nil {
			return fmt.Errorf("failed to generate secret.yaml: %w", err), false
		}
		files["templates/secret.yaml"] = secretYaml
	}

	// Check if any content has changed (excluding version line in Chart.yaml)
	if !chartContentChanged(chartDir, files) {
		if verbose {
			fmt.Printf("  No changes detected, skipping %s\n", chartName)
		}
		return nil, false
	}

	// Content has changed - bump version and regenerate Chart.yaml
	newVersion := bumpPatchVersion(currentVersion)
	chartYaml, err = generateChartYaml(def, newVersion)
	if err != nil {
		return fmt.Errorf("failed to generate Chart.yaml: %w", err), false
	}
	files["Chart.yaml"] = chartYaml

	if verbose {
		fmt.Printf("  Changes detected, bumping version %s -> %s\n", currentVersion, newVersion)
	}

	// Create directories and write all files
	if err := os.MkdirAll(templatesDir, 0755); err != nil {
		return fmt.Errorf("failed to create chart directory: %w", err), false
	}

	for relPath, content := range files {
		fullPath := filepath.Join(chartDir, relPath)
		if err := os.WriteFile(fullPath, []byte(content), 0644); err != nil {
			return fmt.Errorf("failed to write %s: %w", relPath, err), false
		}
	}

	return nil, true
}

func sanitizeChartName(name string) string {
	// Replace underscores with hyphens
	name = strings.ReplaceAll(name, "_", "-")
	// Convert to lowercase
	name = strings.ToLower(name)
	// Remove any characters that aren't alphanumeric or hyphens
	reg := regexp.MustCompile("[^a-z0-9-]")
	name = reg.ReplaceAllString(name, "")
	// Remove consecutive hyphens
	reg = regexp.MustCompile("-+")
	name = reg.ReplaceAllString(name, "-")
	// Trim hyphens from start and end
	name = strings.Trim(name, "-")
	return name
}

func loadTemplate(name string) (string, error) {
	content, err := templateFS.ReadFile("templates/" + name)
	if err != nil {
		return "", fmt.Errorf("failed to read template %s: %w", name, err)
	}
	return string(content), nil
}

// getCurrentChartVersion reads the existing Chart.yaml (if it exists) and returns the current version.
// If the chart doesn't exist or version can't be parsed, returns "1.0.0".
func getCurrentChartVersion(chartName string) string {
	chartPath := filepath.Join(outputDir, chartName, "Chart.yaml")

	file, err := os.Open(chartPath)
	if err != nil {
		// Chart doesn't exist yet, start at 1.0.0
		return "1.0.0"
	}
	defer file.Close()

	// Parse the Chart.yaml to find the version line
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "version:") {
			versionStr := strings.TrimSpace(strings.TrimPrefix(line, "version:"))
			// Remove quotes if present
			versionStr = strings.Trim(versionStr, "\"'")
			return versionStr
		}
	}

	// No version found, start at 1.0.0
	return "1.0.0"
}

// bumpPatchVersion increments the patch version of a semver string.
// If the version can't be parsed, returns "1.0.0".
func bumpPatchVersion(version string) string {
	v, err := semver.NewVersion(version)
	if err != nil {
		return "1.0.0"
	}
	return v.IncPatch().String()
}

func generateChartYaml(def IntegrationDefinition, version string) (string, error) {
	tmplContent, err := loadTemplate("Chart.yaml.tmpl")
	if err != nil {
		return "", err
	}

	tmpl, err := template.New("chart").Parse(tmplContent)
	if err != nil {
		return "", err
	}

	chartName := sanitizeChartName(def.Name)

	data := struct {
		Name    string
		Title   string
		Version string
	}{
		Name:    chartName,
		Title:   def.Title,
		Version: version,
	}

	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, data); err != nil {
		return "", err
	}

	return buf.String(), nil
}

func generateValuesYaml(def IntegrationDefinition) (string, error) {
	tmplContent, err := loadTemplate("values.yaml.tmpl")
	if err != nil {
		return "", err
	}

	funcMap := template.FuncMap{
		"formatDefaultValue": formatDefaultValue,
	}

	tmpl, err := template.New("values").Funcs(funcMap).Parse(tmplContent)
	if err != nil {
		return "", err
	}

	data := struct {
		IntegrationDefinitionName string
		ConfigFields              []ConfigField
		MaskedConfigFields        []ConfigField
		AuthSections              []AuthSection
		HasSecretFields           bool
	}{
		IntegrationDefinitionName: def.Name,
		ConfigFields:              getNonMaskedConfigFields(def),
		MaskedConfigFields:        getMaskedConfigFields(def),
		AuthSections:              getFlattenedAuthSections(def),
		HasSecretFields:           hasSecretFields(def),
	}

	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, data); err != nil {
		return "", err
	}

	return buf.String(), nil
}

func generateSecretYaml(def IntegrationDefinition) (string, error) {
	tmplContent, err := loadTemplate("secret.yaml.tmpl")
	if err != nil {
		return "", err
	}

	tmpl, err := template.New("secret").Parse(tmplContent)
	if err != nil {
		return "", err
	}

	data := struct {
		MaskedConfigFields []ConfigField
		AuthFields         []ConfigField
	}{
		MaskedConfigFields: getMaskedConfigFields(def),
		AuthFields:         getAllAuthFields(def),
	}

	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, data); err != nil {
		return "", err
	}

	return buf.String(), nil
}

func formatDefaultValue(val any) string {
	if val == nil {
		return ""
	}
	switch v := val.(type) {
	case string:
		if v == "" {
			return "\"\""
		}
		return fmt.Sprintf("%q", v)
	case bool:
		return fmt.Sprintf("%t", v)
	case float64:
		return fmt.Sprintf("%v", v)
	default:
		// For complex types, marshal to JSON
		b, err := json.Marshal(v)
		if err != nil {
			return fmt.Sprintf("%v", v)
		}
		return string(b)
	}
}

func generateIntegrationInstanceYaml(def IntegrationDefinition) (string, error) {
	tmplContent, err := loadTemplate("integrationinstance.yaml.tmpl")
	if err != nil {
		return "", err
	}

	tmpl, err := template.New("instance").Parse(tmplContent)
	if err != nil {
		return "", err
	}

	data := struct {
		IntegrationDefinitionName string
		ConfigFields              []ConfigField
		HasSecretFields           bool
		HasAuthSections           bool
	}{
		IntegrationDefinitionName: def.Name,
		ConfigFields:              getNonMaskedConfigFields(def),
		HasSecretFields:           hasSecretFields(def),
		HasAuthSections:           len(def.AuthSections) > 0,
	}

	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, data); err != nil {
		return "", err
	}

	return buf.String(), nil
}
