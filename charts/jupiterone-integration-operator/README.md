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
| `nameOverride` | Overrides the chart name used in the `app.kubernetes.io/name` label. | `""` |
| `controllerManager.replicas` | Manager replicas. Leader election is on, so extra replicas are standby only. | `1` |
| `controllerManager.container.image.repository` | Manager image repository. | `ghcr.io/jupiterone/jupiterone-integration-operator` |
| `controllerManager.container.image.tag` | Manager image tag. Empty uses the chart `appVersion`. | `""` |
| `controllerManager.container.args` | Manager command-line flags. | `--leader-elect`, `--metrics-bind-address=:8443`, `--health-probe-bind-address=:8081` |
| `controllerManager.container.env` | Extra environment variables on the manager as a `KEY: value` map (`JOB_TTL_SECONDS`, `JOB_ACTIVE_DEADLINE_SECONDS`, `ASM_CACHE_TTL_SECONDS`, `AWS_REGION`, `LOG_LEVEL`, `HTTP_PROXY`, ...). | `JOB_TTL_SECONDS: "604800"` |
| `controllerManager.container.resources` | Manager container requests and limits. | `100m`/`64Mi` requests, `500m`/`512Mi` limits |
| `controllerManager.container.livenessProbe` | Manager liveness probe. | `GET /healthz` on `8081` |
| `controllerManager.container.readinessProbe` | Manager readiness probe. | `GET /readyz` on `8081` |
| `controllerManager.container.securityContext` | Manager container security context. | `allowPrivilegeEscalation: false`, drop `ALL` |
| `controllerManager.securityContext` | Manager pod security context. | `runAsNonRoot: true`, seccomp `RuntimeDefault` |
| `controllerManager.pod.labels` | Extra labels on the manager pod. | `{}` |
| `controllerManager.terminationGracePeriodSeconds` | Manager pod termination grace period. | `10` |
| `controllerManager.serviceAccountName` | Name of the operator ServiceAccount. | `jupiterone-integration-operator-controller-manager` |
| `controllerManager.serviceAccount.annotations` | Annotations on the operator ServiceAccount. Set the IRSA role here when the operator reads credentials from AWS Secrets Manager. | `{}` |
| `controllerManager.imageRegistry` | Registry that replaces `ghcr.io` for integration job images (`<registry>/jupiterone/graph-<name>:latest`). Hostname only. | `""` |
| `controllerManager.disableImageSignatureCheck` | Skip cosign signature verification of integration job images. | `false` |
| `controllerManager.imagePullSecrets` | `imagePullSecrets` for the manager pod and every integration job pod. | `[]` |
| `controllerManager.jobResources` | Requests and limits applied to integration job containers. | `{}` |
| `rbac.enable` | Create the operator ServiceAccount, Roles and bindings. | `true` |
| `metrics.enable` | Create the metrics Service. Remove `--metrics-bind-address` from `args` when disabling. | `true` |
| `prometheus.enable` | Create a `ServiceMonitor` for the metrics Service. | `false` |
| `certmanager.enable` | Issue the metrics serving certificate with cert-manager. | `false` |
| `crd.keep` | Keep the cert-manager Certificate on uninstall (`helm.sh/resource-policy: keep`). | `false` |
| `networkPolicy.enable` | Create a NetworkPolicy allowing metrics scrapes from namespaces labeled `metrics: enabled`. | `false` |
| `integration.create` | Create the `kubernetes-managed` integration ServiceAccount, ClusterRole and ClusterRoleBinding. | `true` |
| `integration.serviceAccountName` | ServiceAccount used by `kubernetes-managed` integration job pods (`K8S_INTEGRATION_SERVICE_ACCOUNT`). | `jupiterone` |
| `integration.serviceAccountNamespace` | Namespace of that ServiceAccount. Changing it is not supported. | `jupiterone` |
| `integration.serviceAccount.annotations` | Annotations on the `kubernetes-managed` integration ServiceAccount. | `{}` |
| `integration.jobServiceAccount.create` | Create a ServiceAccount for all other integration job pods. | `false` |
| `integration.jobServiceAccount.name` | Name of that ServiceAccount. Defaults to `jupiterone-integration-job` when created. Set without `create` to reference one managed elsewhere. | `""` |
| `integration.jobServiceAccount.annotations` | Annotations on the integration job ServiceAccount. Set the IRSA role here to give job pods an AWS identity. | `{}` |

Environment variables the manager reads that have no dedicated value are set
through `controllerManager.container.env`:

| Variable | Description | Default |
|---|---|---|
| `JOB_TTL_SECONDS` | Seconds a finished `IntegrationInstanceJob` and its Job are kept. | `2592000`; the chart sets `604800` |
| `JOB_ACTIVE_DEADLINE_SECONDS` | `activeDeadlineSeconds` on each integration Job. | `86400` |
| `ASM_CACHE_TTL_SECONDS` | Cache TTL for AWS Secrets Manager lookups; `0` disables. | `60` |
| `AWS_REGION` | Region for the AWS SDK default chain when a CR omits `region`. | unset |
| `LOG_LEVEL` | `debug`, `info`, `warn` or `error`. | `info` |
| `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY` | Proxy settings; also injected into integration job pods. | unset |

### ServiceAccount annotations (IRSA)

Every ServiceAccount the chart creates accepts annotations, so an IAM role can
be attached without editing rendered manifests:

```yaml
controllerManager:
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/jupiterone-integration-operator
```

The operator needs that role only when a CR reads credentials from AWS Secrets
Manager (`apiTokenSource` / `secretSource` with `provider: awsSecretsManager`).
Integration job pods and the `kubernetes-managed` ServiceAccount take their
annotations from `integration.jobServiceAccount.annotations` and
`integration.serviceAccount.annotations`; see
[AWS Access for Integration Job Pods (IRSA)](#aws-access-for-integration-job-pods-irsa).
Trust policies and permission policies are in the operator README under
[AWS authentication (IRSA)](https://github.com/JupiterOne/jupiterone-integration-operator#aws-authentication-irsa).

### AWS Secrets Manager Example

```yaml
controllerManager:
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/jupiterone-integration-operator
  container:
    env:
      AWS_REGION: us-east-1
      ASM_CACHE_TTL_SECONDS: "60"
```

Then reference the secret from the runner chart (`apiTokenSource`) or an
`IntegrationInstance` (`secretSource`).

### Metrics with Prometheus and cert-manager

```yaml
metrics:
  enable: true
prometheus:
  enable: true
certmanager:
  enable: true
networkPolicy:
  enable: true
```

cert-manager issues `metrics-server-cert` for
`jupiterone-integration-operator-metrics-service.<namespace>.svc`, the
ServiceMonitor scrapes it over TLS, and the NetworkPolicy admits scrapes only
from namespaces labeled `metrics: enabled`. Without `certmanager.enable` the
ServiceMonitor uses `insecureSkipVerify: true`.

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

### AWS Access for Integration Job Pods (IRSA)

Integration job pods run under the `default` ServiceAccount, which normally has
no AWS identity. Integrations that call AWS -- for example SBOM for AWS ECR --
need one. Set `integration.jobServiceAccount` and the chart creates the
ServiceAccount, annotates it for IRSA, and points the operator at it through
`INTEGRATION_JOB_SERVICE_ACCOUNT`, so every integration job pod runs with that
identity.

```yaml
integration:
  jobServiceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/jupiterone-integration-job
```

The `kubernetes-managed` integration keeps its own ServiceAccount (it is bound
to the in-cluster read ClusterRole) and is annotated separately:

```yaml
integration:
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/jupiterone-kubernetes-managed
```

The operator itself needs a role only when a CR resolves credentials from AWS
Secrets Manager:

```yaml
controllerManager:
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/jupiterone-integration-operator
```

**Same-account ECR.** Grant the job role ECR read directly
(`ecr:GetAuthorizationToken` on `*`, plus `ecr:BatchGetImage`,
`ecr:GetDownloadUrlForLayer`, `ecr:BatchCheckLayerAvailability`,
`ecr:DescribeRepositories`, `ecr:DescribeImages`, `ecr:ListImages`,
`ecr:ListTagsForResource` on the repository ARNs).

**Cross-account ECR.** Grant the job role only `sts:AssumeRole` on the role in
the registry's account; that role holds the ECR permissions and trusts the job
role. That trust is between two identities the customer owns: the `Principal`
is the customer's job pod role, not a JupiterOne AWS account. Several registries
means one such role per account and one `sts:AssumeRole` resource per target.

This ServiceAccount is shared by every integration job pod in the release, so
keep its own policy to the `sts:AssumeRole` targets it needs and leave the ECR
permissions on the assumed roles. Where a workload needs stronger separation,
install a second operator and runner in their own namespace with their own
`integration.jobServiceAccount`.

Trust policies, IAM policy documents and the step-by-step SBOM for AWS ECR
setup are in the operator repository:
[AWS authentication (IRSA)](https://github.com/JupiterOne/jupiterone-integration-operator#aws-authentication-irsa).

Requires the operator release that adds `INTEGRATION_JOB_SERVICE_ACCOUNT`
(`v0.4.0`). On older operators the env var is ignored and job pods keep using
the `default` ServiceAccount.

### Job Resources Example

If your cluster enforces resource policies (e.g. Kyverno `require-requests-limits`), configure resource requirements for integration job containers:

```yaml
controllerManager:
  jobResources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: "1"
      memory: 1Gi
```

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
