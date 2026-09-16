# JupiterOne Integration Runner

This chart installs a single `IntegrationRunner` custom resource. The
[JupiterOne Integration Operator](../jupiterone-integration-operator) reconciles
it: it registers the runner with JupiterOne using your API token, then spawns a
Kubernetes Job for every integration instance assigned to the runner. The
chart itself creates no Deployment, Pod or ServiceAccount.

## Prerequisites

- Kubernetes 1.16+
- Helm 3+
- The `jupiterone-integration-operator` chart installed in the same cluster
- A JupiterOne account API token with **Collector -- CRUD** and **Shared:
  Graph Data -- Read/Write** permissions (Settings > Account API Tokens)
- Your JupiterOne account ID (Settings > Account Management)

## Installation

### 1. Add the JupiterOne Helm Repository

```console
helm repo add jupiterone https://jupiterone.github.io/helm-charts
helm repo update
```

### 2. Install the Runner

Install into the namespace the operator watches (`jupiterone` by default).
Replace `<account-id>` and `<api-token>`:

```console
helm install integration-runner jupiterone/jupiterone-integration-runner \
  --namespace jupiterone \
  --set accountID=<account-id> \
  --set apiToken=<api-token>
```

The chart fails to render if `accountID` is missing or `apiToken` is left at
its placeholder while `createSecret` is true.

### 3. Verify Installation

```console
kubectl get integrationrunner -n jupiterone
# NAME                 STATE     REGISTRATION
# integration-runner   running   registered
```

Registration takes about 30 seconds. If `STATE` stays `pending`, check the
operator logs:

```console
kubectl logs -n jupiterone deploy/jupiterone-integration-operator-controller-manager
```

## Parameters

| Parameter | Description | Default |
|---|---|---|
| `accountID` | JupiterOne account ID. Required. | `<account-id>` |
| `jupiterOneEnvironment` | JupiterOne environment the runner connects to (`us`, `eu`, `gov`, ...). | `us` |
| `syncIntervalSeconds` | How often, in seconds, the runner polls JupiterOne for work. | `30` |
| `createSecret` | Create a Kubernetes Secret named `secretAPITokenName` from `apiToken`. Set `false` when the Secret is managed elsewhere or the token comes from AWS Secrets Manager. | `true` |
| `apiToken` | JupiterOne API token. Required when `createSecret` is `true`. | `<api-token>` |
| `secretAPITokenName` | Name of the Kubernetes Secret holding the token under the `token` key. | `j1token` |
| `apiTokenSource.provider` | Where the runner reads the token: `kubernetes` or `awsSecretsManager`. Empty uses `secretAPITokenName`. | `""` |
| `apiTokenSource.kubernetes.name` | Kubernetes Secret name when `provider` is `kubernetes`. Defaults to `secretAPITokenName`. | `""` |
| `apiTokenSource.awsSecretsManager.secretId` | ARN or name of the AWS Secrets Manager secret. Required when `provider` is `awsSecretsManager`. | `""` |
| `apiTokenSource.awsSecretsManager.region` | Region of the secret. Defaults to the operator's region. | `""` |
| `apiTokenSource.awsSecretsManager.versionStage` | Staging label to read. Defaults to `AWSCURRENT`. | `""` |

### Existing Kubernetes Secret

Create the Secret yourself, with the token under the `token` key, and point the
runner at it:

```console
kubectl create secret generic j1token -n jupiterone --from-literal=token=<api-token>

helm install integration-runner jupiterone/jupiterone-integration-runner \
  --namespace jupiterone \
  --set accountID=<account-id> \
  --set createSecret=false \
  --set secretAPITokenName=j1token
```

### AWS Secrets Manager

Store the token as a JSON object, `{ "token": "<api-token>" }`, and reference
it. The operator resolves the secret, so the **operator's** ServiceAccount
needs an IAM role with `secretsmanager:GetSecretValue` on it -- see
[AWS authentication (IRSA)](https://github.com/JupiterOne/jupiterone-integration-operator#aws-authentication-irsa).

```yaml
# values.yaml
accountID: <account-id>
createSecret: false
apiTokenSource:
  provider: awsSecretsManager
  awsSecretsManager:
    secretId: jupiterone/runner-api-token
    region: us-east-1
```

```console
helm install integration-runner jupiterone/jupiterone-integration-runner \
  --namespace jupiterone -f values.yaml
```

## ServiceAccounts and AWS identity

The runner has no pod, so this chart has no ServiceAccount to annotate. The
identities involved are all configured on the operator chart:

| Workload | Chart value on `jupiterone-integration-operator` |
|---|---|
| Operator (reads AWS Secrets Manager) | `controllerManager.serviceAccount.annotations` |
| Integration job pods spawned for this runner | `integration.jobServiceAccount` |
| `kubernetes-managed` integration job pods | `integration.serviceAccount.annotations` |

Integrations that call AWS from the job pod -- for example SBOM for AWS ECR --
get their IAM role through those values, not through this chart.

## Usage

### Set Default Namespace

```console
kubectl config set-context --current --namespace jupiterone
```

### Inspect the runner and its jobs

```console
kubectl get integrationrunner
kubectl get integrationinstancejob
kubectl get job
```

### Multiple runners

Each release is one runner. Install the chart again with a different release
name to add another runner to the same account, or into another namespace
watched by its own operator.

## Updating the Runner

```console
helm repo update
helm upgrade integration-runner jupiterone/jupiterone-integration-runner --namespace jupiterone --reuse-values
```

## Uninstalling

```console
helm uninstall integration-runner --namespace jupiterone
```

The operator deregisters the runner from JupiterOne. Integration instances
assigned to it stop running until reassigned.

## Troubleshooting

- **`STATE` stays `pending`:** the API token lacks Collector CRUD permission, or `jupiterOneEnvironment` does not match the account's region. Check the operator logs.
- **`secret not found`:** `createSecret=false` but no Secret named `secretAPITokenName` exists in the release namespace, or it lacks a `token` key.
- **`AWS Secrets Manager provider is not configured`:** the operator has no AWS credentials. Annotate its ServiceAccount for IRSA (operator chart `controllerManager.serviceAccount.annotations`).
- **Integration jobs fail with `Configuration failure`:** the job pod has no AWS identity. Set `integration.jobServiceAccount` on the operator chart.

## Support

If you need help, please contact JupiterOne support
