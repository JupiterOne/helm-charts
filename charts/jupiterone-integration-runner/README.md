# JupiterOne Integration Runner

This chart installs a single instance of the Runner using a Custom Resource.

## Prerequisites

- Kubernetes 1.16+
- Helm 3+
- Access to a JupiterOne account with API credentials
- JupiterOne Integration Operator helm chart installed

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

### 3. Install the Runner

Replace `<collectorID>`, `<accountID>`, and `<authToken>` with your JupiterOne credentials.

```console
helm install integration-runner jupiterone/jupiterone-integration-runner \
  --namespace jupiterone \
  --set collectorID=<collectorID> \
  --set accountID=<accountID> \
  --set authToken=<authToken>
```

#### Example

```console
helm install integration-runner jupiterone/jupiterone-integration-runner \
  --namespace jupiterone \
  --set collectorID=abcd1234 \
  --set accountID=efgh5678 \
  --set authToken=your-token-here
```

### 4. Verify Installation

Check that the runner is installed

```console
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
