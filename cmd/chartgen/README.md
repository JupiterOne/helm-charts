# chartgen

A CLI tool that generates Helm charts for JupiterOne integrations by fetching integration definitions from the JupiterOne GraphQL API.

## Overview

`chartgen` automates the creation of Helm charts for JupiterOne integrations that support the collector execution model. It:

- Fetches integration definitions from the JupiterOne GraphQL API
- Generates properly structured Helm charts with `IntegrationInstance` custom resources
- Handles configuration fields, authentication sections, and secrets
- Automatically increments chart versions when regenerating existing charts

## Prerequisites

- Go 1.21 or later
- JupiterOne API key
- JupiterOne account ID

## Building

```bash
go build -o chartgen ./cmd/chartgen
```

## Usage

```bash
chartgen [flags]
```

### Flags

| Flag | Short | Description | Required | Default |
|------|-------|-------------|----------|---------|
| `--api-key` | `-k` | JupiterOne API key | Yes | - |
| `--account-id` | `-a` | JupiterOne account ID | Yes | - |
| `--output` | `-o` | Output directory for generated charts | No | `./charts` |
| `--name` | `-n` | Generate chart for a specific integration by name | No | - |
| `--write` | `-w` | Write files to disk (without this flag, runs in dry-run mode) | No | `false` |
| `--verbose` | `-v` | Enable verbose output | No | `false` |

### Environment Variables

You can also set credentials via environment variables:

```bash
export J1_API_KEY="your-api-key"
export J1_ACCOUNT_ID="your-account-id"
```

## Examples

### Dry Run (Preview)

See what charts would be generated without writing files:

```bash
./chartgen -k $J1_API_KEY -a $J1_ACCOUNT_ID
```

### Generate All Charts

Generate charts for all integrations that support collectors:

```bash
./chartgen -k $J1_API_KEY -a $J1_ACCOUNT_ID -w
```

### Generate a Specific Chart

Generate a chart for a single integration:

```bash
./chartgen -k $J1_API_KEY -a $J1_ACCOUNT_ID -n github -w
```

### Verbose Output

See detailed information during generation:

```bash
./chartgen -k $J1_API_KEY -a $J1_ACCOUNT_ID -n github -w -v
```

### Custom Output Directory

Generate charts to a different directory:

```bash
./chartgen -k $J1_API_KEY -a $J1_ACCOUNT_ID -o ./my-charts -w
```

## Generated Chart Structure

Each generated chart has the following structure:

```
<integration-name>/
├── Chart.yaml              # Chart metadata with auto-incremented version
├── values.yaml             # Configuration values with documentation
├── .helmignore             # Files to ignore when packaging
└── templates/
    ├── integrationinstance.yaml  # IntegrationInstance CR template
    └── secret.yaml               # Secret template (if integration has auth)
```

## Version Management

When regenerating an existing chart, `chartgen` automatically:

1. Reads the current version from the existing `Chart.yaml`
2. Increments the patch version (e.g., `1.0.4` → `1.0.5`)
3. Uses the new version in the generated chart

For new charts, the version starts at `1.0.0`.

## Values.yaml Structure

Generated `values.yaml` files include:

- **Common configuration**: `collectorName`, `pollingInterval`, `secretName`, `createSecret`
- **Integration Configuration**: Non-sensitive configuration fields
- **Sensitive Configuration**: Authentication fields organized by auth section

Example:

```yaml
collectorName: runner
pollingInterval: "ONE_WEEK"
secretName: "github-secret"
createSecret: true

# Integration Configuration
# ...

# Sensitive Configuration (stored in Secret)
secret:
  # ---------------------------------------------------------------------------
  # Token
  # ---------------------------------------------------------------------------
  # selectedAuthType: "token"

  # GitHub App Token
  # githubAppToken:
```

## CI/CD Integration

The tool is designed to be run in CI/CD pipelines to keep charts up-to-date:

```yaml
# Example GitHub Actions workflow
- name: Generate Charts
  run: |
    ./chartgen -k ${{ secrets.J1_API_KEY }} -a ${{ secrets.J1_ACCOUNT_ID }} -w

- name: Check for changes
  run: |
    git diff --exit-code charts/ || echo "Charts updated"
```

## Supported Integrations

Only integrations with `supportsCollectors: true` in their platform features are generated. Run in dry-run mode to see the list of supported integrations:

```bash
./chartgen -k $J1_API_KEY -a $J1_ACCOUNT_ID
```
