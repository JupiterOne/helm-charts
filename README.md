# JupiterOne Kubernetes Helm Charts

This repository contains Helm charts for deploying JupiterOne integrations in your Kubernetes cluster using the JupiterOne Integration Operator.

## Prerequisites

- Kubernetes cluster (1.19+)
- [Helm](https://helm.sh) 3.0+
- JupiterOne account with API access
- JupiterOne Integration Operator installed in your cluster

## Usage

Add the JupiterOne Helm repository:

```console
helm repo add jupiterone https://jupiterone.github.io/helm-charts
helm repo update
```

Search for available charts:

```console
helm search repo jupiterone
```

## Available Charts

### Infrastructure Charts

| Chart | Description |
|-------|-------------|
| `jupiterone-integration-operator` | The operator that manages integration instances |
| `jupiterone-integration-runner` | The runner that executes integration jobs |

### Integration Charts

Integration charts create `IntegrationInstance` custom resources that are managed by the operator. Available integrations include:

- `github` - GitHub integration
- `gitlab` - GitLab integration
- `jira` - Jira integration
- `bitbucket` - Bitbucket integration
- `jenkins` - Jenkins integration
- `artifactory` - JFrog Artifactory integration
- `hashicorp-vault` - HashiCorp Vault integration
- `terraform-cloud` - Terraform Cloud integration
- And many more...

Run `helm search repo jupiterone` for the complete list.

## Installing an Integration

1. First, ensure the operator and runner are installed:

```console
helm install j1-operator jupiterone/jupiterone-integration-operator \
  --namespace jupiterone \
  --create-namespace

helm install j1-runner jupiterone/jupiterone-integration-runner \
  --namespace jupiterone
```

2. Install an integration chart with your configuration:

```console
helm install my-github jupiterone/github \
  --namespace jupiterone \
  --set secret.selectedAuthType="token" \
  --set secret.githubAppToken="your-token"
```

Or create a values file:

```yaml
# values.yaml
collectorName: runner
pollingInterval: "ONE_DAY"

secret:
  selectedAuthType: "token"
  githubAppToken: "your-github-token"
```

```console
helm install my-github jupiterone/github \
  --namespace jupiterone \
  -f values.yaml
```

## Configuration

Each integration chart supports the following common configuration options:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `collectorName` | Name of the IntegrationRunner in the same namespace | `runner` |
| `pollingInterval` | How often the integration runs | `ONE_WEEK` |
| `secretName` | Name of the Kubernetes secret for credentials | `<integration>-secret` |
| `createSecret` | Whether to create the secret from values | `true` |

Polling interval options:
- `DISABLED`
- `THIRTY_MINUTES`
- `ONE_HOUR`
- `FOUR_HOURS`
- `EIGHT_HOURS`
- `TWELVE_HOURS`
- `ONE_DAY`
- `ONE_WEEK`

For integration-specific configuration options, see the `values.yaml` file in each chart or run:

```console
helm show values jupiterone/<chart-name>
```

## Managing Secrets Externally

If you prefer to manage secrets outside of Helm (e.g., using External Secrets Operator or sealed-secrets):

1. Create your secret manually with the required keys
2. Install the chart with `createSecret: false` and provide the secret name:

```console
helm install my-github jupiterone/github \
  --namespace jupiterone \
  --set createSecret=false \
  --set secretName=my-existing-secret
```

## Upgrading

```console
helm repo update
helm upgrade my-github jupiterone/github --namespace jupiterone
```

## Uninstalling

```console
helm uninstall my-github --namespace jupiterone
```

## Development

For information about generating and maintaining these charts, see the [chartgen documentation](cmd/chartgen/README.md).

## Support

For issues with these Helm charts, please open an issue in this repository.

For JupiterOne platform support, visit [jupiterone.io](https://jupiterone.io).
