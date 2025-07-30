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

Replace `<collectorID>`, `<accountID>`, and `<authToken>` with your JupiterOne credentials.

```console
helm install kubernetes-operator jupiterone/jupiterone-integration-operator \
  --namespace jupiterone \
  --set runner.create=true \
  --set runner.collectorID=<collectorID> \
  --set runner.accountID=<accountID> \
  --set runner.authToken=<authToken>
```

#### Example

```console
helm install kubernetes-operator jupiterone/jupiterone-integration-operator \
  --namespace jupiterone \
  --set runner.create=true \
  --set runner.collectorID=abcd1234 \
  --set runner.accountID=efgh5678 \
  --set runner.authToken=your-token-here
```

### 4. Verify Installation

Check that the operator and runner are installed:

```console
kubectl get pods -n jupiterone
kubectl get integrationrunner -n jupiterone
```

## Configuration

You can customize the installation using Helm values. For example, to set resource limits or configure logging, update your `values.yaml` or pass additional flags to `helm install`.

Refer to the [values.yaml](./values.yaml) for all available configuration options.

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
helm upgrade kubernetes-operator jupiterone/jupiterone-integration-operator --namespace jupiterone
```

## Uninstalling

To remove the operator and all related resources:

```console
helm uninstall kubernetes-operator --namespace jupiterone
kubectl delete namespace jupiterone
```

## Troubleshooting

- **Pod not starting:** Check logs with `kubectl logs <pod-name>`.
- **CRDs not found:** Ensure the operator pod is running and healthy.
- **Authentication errors:** Double-check your `collectorID`, `accountID`, and `authToken`.

## Support

If you need help, please contact JupiterOne support
