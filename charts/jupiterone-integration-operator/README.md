# JupiterOne Integration Operator

This operator installs in a Kubernetes environment and manages several Custom Resource Definitions (CRDs) for managing JupiterOne integrations.

The operator installs an `IntegrationRunner` type which manages a connection to JupiterOne's API. The API then delegates integrations that need to run on your cluster.

## Prerequisites

- Kubernetes 1.16+
- Helm 3+
- Access to a JupiterOne account with API credentials

## Installation

### 1. Add the JupiterOne Helm Repository

```console
helm repo add jupiterone https://jupiterone.github.io/helm-charts
helm repo update
```

### 2. Create the Namespace

All resources are created in the namespace `jupiterone`. If it does not exist, create it:

```console
kubectl create namespace jupiterone
```

### 3. Install the Operator

```console
helm install integration-operator jupiterone/jupiterone-integration-operator --namespace jupiterone
```

### 4. Verify Installation

Check that the operator is running:

```console
kubectl get pods -n jupiterone
```

## Configuration

You can customize the installation using Helm values. For example, to set resource limits or configure logging, update your `values.yaml` or pass additional flags to `helm install`.

Refer to the [values.yaml](./values.yaml) for all available configuration options.

## Parameters

| Parameter | Description | Default |
|---|---|---|
| `controllerManager.imageRegistry` | Image registry override for private registry environments. When set, integration job images are pulled from this registry instead of `ghcr.io`. | `""` |
| `controllerManager.imagePullSecrets` | Secrets for pulling images from private registries. Applied to both the operator Deployment and propagated to spawned integration job pods. | `[]` |
| `controllerManager.disableImageSignatureCheck` | Disable cosign image signature verification for integration job images. Set to `true` when using registries that don't mirror ghcr.io cosign signatures. | `false` |

### Private Registry Example

Create a custom values file (e.g., `custom-values.yaml`) with the private registry configuration:

```yaml
controllerManager:
  imageRegistry: "myregistry.example.com"
  imagePullSecrets:
    - name: my-registry-secret
  disableImageSignatureCheck: true  # Set to true if your registry doesn't mirror ghcr.io cosign signatures
```

Then install (or upgrade) using the values file:

```console
helm install integration-operator jupiterone/jupiterone-integration-operator \
  --namespace jupiterone \
  -f custom-values.yaml
```

> **Note:** `disableImageSignatureCheck` is independent of `imageRegistry`. Cosign verification may work through registry proxies since it resolves signatures against the original source. Only disable it if verification fails in your environment.

## Usage

### Set Default Namespace

To avoid specifying `-n jupiterone` in every command:

```console
kubectl config set-context --current --namespace jupiterone
```

### List Integration Runners

```console
kubectl get integrationrunner
```

### List Integration Instance Jobs

```console
kubectl get integrationinstancejob
```

### List Kubernetes Jobs

```console
kubectl get job
```

## Updating the Operator

To upgrade to a newer version:

```console
helm repo update
helm upgrade integration-operator jupiterone/jupiterone-integration-operator --namespace jupiterone
```

## Uninstalling

To remove the operator and all related resources:

```console
helm uninstall integration-operator --namespace jupiterone
kubectl delete namespace jupiterone
```

## Troubleshooting

- **Pod not starting:** Check logs with `kubectl logs <pod-name>`.
- **CRDs not found:** Ensure the operator pod is running and healthy.
- **Authentication errors:** Double-check your `collectorID`, `accountID`, and `authToken`.

## Support

If you need help, please contact JupiterOne support
