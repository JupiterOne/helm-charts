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

If your cluster cannot reach GitHub, see [Installing without GitHub access](#installing-without-github-access).

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

### Installing without GitHub access

The charts are published only to the GitHub chart repository. Download them on
a machine with GitHub access and copy the `.tgz` files to one that can reach
your cluster:

```console
helm pull jupiterone/jupiterone-integration-operator
helm pull jupiterone/jupiterone-integration-runner
```

The operator image and the integration images are published to `ghcr.io` and
to AWS Public ECR (`public.ecr.aws/jupiterone`). Serve them to the cluster from
a [private registry mirror](#private-registry-mirror) of Public ECR, then
install from the `.tgz` files with the mirror's values file:

```console
kubectl create namespace jupiterone

helm install integration-operator ./jupiterone-integration-operator-<version>.tgz \
  --namespace jupiterone \
  -f mirror-values.yaml

helm install <runnerName> ./jupiterone-integration-runner-<version>.tgz \
  --namespace jupiterone \
  --set apiToken=<apiToken> \
  --set accountID=<accountID>
```

Pulling from `public.ecr.aws` directly also works
(`controllerManager.imageRegistry: public.ecr.aws` and the operator image
`public.ecr.aws/jupiterone/jupiterone-integration-operator`), but the cluster
then needs egress to `public.ecr.aws`, `tuf-repo-cdn.sigstore.dev` and the
CloudFront host `public.ecr.aws` redirects image layer downloads to. AWS does
not document that hostname and can change it, so a mirror is the recommended
way to avoid a broad CloudFront allowlist.

## Configuration

You can customize the installation using Helm values. For example, to set resource limits or configure logging, update your `values.yaml` or pass additional flags to `helm install`.

Refer to the [values.yaml](./values.yaml) for all available configuration options.

## Parameters

| Parameter | Description | Default |
|---|---|---|
| `nameOverride` | Overrides the chart name used in the `app.kubernetes.io/name` label. | `""` |
| `commonLabels` | Labels on every object this chart creates, directly or indirectly. See [Common labels and annotations](#common-labels-and-annotations). | `{}` |
| `commonAnnotations` | Annotations on the same objects. | `{}` |
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
| `controllerManager.deployment.labels` / `.annotations` | Extra labels and annotations on the manager Deployment. | `{}` |
| `controllerManager.pod.labels` | Extra labels on the manager pod. | `{}` |
| `controllerManager.pod.annotations` | Extra annotations on the manager pod. | `{}` |
| `controllerManager.nodeSelector` / `.tolerations` / `.affinity` | Scheduling for the manager pod. | unset |
| `controllerManager.terminationGracePeriodSeconds` | Manager pod termination grace period. | `10` |
| `controllerManager.serviceAccountName` | Name of the operator ServiceAccount. | `jupiterone-integration-operator-controller-manager` |
| `controllerManager.serviceAccount.annotations` | Annotations on the operator ServiceAccount. Set the IRSA role here when the operator reads credentials from AWS Secrets Manager. | `{}` |
| `controllerManager.imageRegistry` | Registry host plus optional path prefix, without a scheme, that replaces `ghcr.io` for integration job images (`<imageRegistry>/jupiterone/graph-<name>:latest`) and their signatures. See [Private registry mirror](#private-registry-mirror). | `""` |
| `controllerManager.disableImageSignatureCheck` | Skip cosign signature verification of integration job images. Not needed with a mirror that serves the `-signatures` repositories. | `false` |
| `controllerManager.imagePullSecrets` | `imagePullSecrets` for the manager pod and every integration job pod. The operator also uses them to verify signatures against `imageRegistry`; a private mirror needs one. | `[]` |
| `controllerManager.jobResources` | Requests and limits applied to integration job containers. | `{}` |
| `controllerManager.job` | Labels, annotations, scheduling and security context for every integration run. See [Job labels, annotations and scheduling](#job-labels-annotations-and-scheduling). | `{}` |
| `rbac.enable` | Create the operator ServiceAccount, Roles and bindings. | `true` |
| `metrics.enable` | Create the metrics Service. Remove `--metrics-bind-address` from `args` when disabling. | `true` |
| `prometheus.enable` | Create a `ServiceMonitor` for the metrics Service. | `false` |
| `certmanager.enable` | Issue the metrics serving certificate with cert-manager. | `false` |
| `crd.keep` | Annotate the operator CRDs (and the metrics Certificate) with `helm.sh/resource-policy: keep` so `helm uninstall` leaves them, and every `IntegrationRunner`/`IntegrationInstance`/`IntegrationInstanceJob`, in place. | `false` |
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

### Private registry mirror

Run the operator against a registry you control that mirrors AWS Public ECR
(`public.ecr.aws`). Three mirrors are covered below:

1. [AWS ECR pull-through cache](#aws-ecr-pull-through-cache) (recommended on
   AWS). AWS fetches from Public ECR itself, so the cluster network needs no
   CloudFront egress.
2. [Harbor proxy cache](#harbor-proxy-cache).
3. [Artifactory remote Docker repository](#artifactory-remote-docker-repository)
   (JFrog Container Registry or Artifactory Pro).

How the operator uses the mirror:

- `controllerManager.imageRegistry` is the registry host plus an optional path
  prefix, without a scheme, for example
  `<account>.dkr.ecr.<region>.amazonaws.com/<prefix>` or
  `<harbor-host>/<project>`. Integration jobs run
  `<imageRegistry>/jupiterone/graph-<name>:latest`.
- Before a job starts, the operator verifies the image's cosign signature. It
  reads the signature from the `-signatures` repository next to the image,
  `<imageRegistry>/jupiterone/graph-<name>-signatures` (tags
  `sha256-<digest>.sig`). Pull-through and proxy caches fetch these
  repositories on demand, with no extra configuration. If you copy images
  instead of caching them, copy the `-signatures` repositories too.
- Signature verification authenticates to the mirror only with
  `controllerManager.imagePullSecrets`. It does not use node credentials, an IAM
  role on the operator ServiceAccount, or the ServiceAccount's own
  `imagePullSecrets`. Without a pull secret, a private
  mirror returns `401 Unauthorized` and the operator falls back to verifying
  against `ghcr.io`, which fails when the cluster cannot reach GitHub. The log
  line `Image verification failed against custom registry, falling back to
  ghcr.io` means the mirror setup is incomplete.
- Keep `controllerManager.disableImageSignatureCheck: false`.
- Outbound from the cluster, the operator needs the mirror and
  `tuf-repo-cdn.sigstore.dev:443`, where cosign fetches the sigstore trusted
  root on each verification. Nothing else is needed for images or
  verification. The runner still needs the JupiterOne API.

#### AWS ECR pull-through cache

1. Create a pull-through cache rule in the cluster's region. No upstream
   credentials are needed:

   ```console
   aws ecr create-pull-through-cache-rule \
     --ecr-repository-prefix jupiterone-public \
     --upstream-registry-url public.ecr.aws \
     --upstream-registry ecr-public
   ```

2. Grant the node role, in addition to its usual ECR read-only policy, the
   actions that create and import cached repositories. Without them the first
   pull of an image, or of a new `.sig` tag, fails with `NotFound` or
   `NAME_UNKNOWN`:

   ```json
   {
     "Effect": "Allow",
     "Action": ["ecr:CreateRepository", "ecr:BatchImportUpstreamImage"],
     "Resource": "arn:aws:ecr:<region>:<account>:repository/jupiterone-public/*"
   }
   ```

3. Give the identity that mints the pull secret the same two actions plus
   `ecr:GetAuthorizationToken` (on `*`), `ecr:BatchGetImage`,
   `ecr:BatchCheckLayerAvailability` and `ecr:GetDownloadUrlForLayer`.
4. Reach ECR privately with VPC interface endpoints
   `com.amazonaws.<region>.ecr.api` and `com.amazonaws.<region>.ecr.dkr`
   (private DNS on) and an S3 gateway endpoint, which serves the image layers.
5. Keep a `kubernetes.io/dockerconfigjson` pull secret in the operator
   namespace. ECR tokens expire after 12 hours, so refresh it on a schedule,
   for example with the External Secrets Operator `ECRAuthorizationToken`
   generator. Here `ecr-token-minter` is a ServiceAccount whose IAM role has
   the permissions from step 3:

   ```yaml
   apiVersion: generators.external-secrets.io/v1alpha1
   kind: ECRAuthorizationToken
   metadata:
     name: ecr-token
     namespace: jupiterone
   spec:
     region: <region>
     auth:
       jwt:
         serviceAccountRef:
           name: ecr-token-minter
   ---
   apiVersion: external-secrets.io/v1
   kind: ExternalSecret
   metadata:
     name: ecr-pull
     namespace: jupiterone
   spec:
     refreshInterval: 6h
     target:
       name: ecr-pull
       template:
         type: kubernetes.io/dockerconfigjson
         data:
           .dockerconfigjson: '{"auths":{"{{ .proxy_endpoint }}":{"username":"{{ .username }}","password":"{{ .password }}"}}}'
     dataFrom:
       - sourceRef:
           generatorRef:
             apiVersion: generators.external-secrets.io/v1alpha1
             kind: ECRAuthorizationToken
             name: ecr-token
   ```

6. Install with these values:

   ```yaml
   controllerManager:
     container:
       image:
         repository: <account>.dkr.ecr.<region>.amazonaws.com/jupiterone-public/jupiterone/jupiterone-integration-operator
     imageRegistry: <account>.dkr.ecr.<region>.amazonaws.com/jupiterone-public
     imagePullSecrets:
       - name: ecr-pull
   ```

Notes:

- The cache checks Public ECR for a newer tag at most once every 24 hours, so a
  new `latest` integration image can take up to a day to arrive.
- A repository creation template that matches the prefix and sets
  `resourceTags` without a `customRoleArn` stops the cache from creating
  repositories (`repository ... does not exist`). Add a custom role to the
  template or leave it out.

#### Harbor proxy cache

1. Under Registries, create an endpoint with provider `Docker Registry`, URL
   `https://public.ecr.aws`, no credentials. (The `AWS ECR` provider is for
   private ECR.)
2. Create a project, for example `ecr-public`, with Proxy Cache enabled on that
   endpoint.
3. If the project is private, create a robot account with pull access to it and
   store it as a pull secret:

   ```console
   kubectl -n jupiterone create secret docker-registry harbor-pull \
     --docker-server=<harbor-host> \
     --docker-username='robot$ecr-public+<name>' \
     --docker-password=<secret>
   ```

4. Install with these values:

   ```yaml
   controllerManager:
     container:
       image:
         repository: <harbor-host>/ecr-public/jupiterone/jupiterone-integration-operator
     imageRegistry: <harbor-host>/ecr-public
     imagePullSecrets:        # omit only for a public project
       - name: harbor-pull
   ```

Harbor's TLS certificate must chain to a public CA. The nodes and the operator
use the system trust store, and the operator image has no way to add a private
CA.

#### Artifactory remote Docker repository

Works with JFrog Container Registry (JCR) and Artifactory Pro.

1. Create a remote repository, package type Docker, for example `ecr-public`:
   URL `https://public.ecr.aws`, no upstream credentials, Docker API V2,
   Enable Token Authentication on. A metadata retrieval cache period of about
   600 seconds keeps `latest` fresh. With the default Repository Path access
   method, images are addressed as
   `<artifactory-host>/ecr-public/jupiterone/<image>:<tag>`.
2. Create a dedicated pull user, for example `jupiterone-puller` (in the UI on
   JCR, or through the REST API on Pro), and a permission target on
   `ecr-public` granting Read, Annotate and Deploy/Cache. Read alone is not
   enough: Artifactory rejects a pull that misses the cache unless the user can
   cache the artifact, and `latest` changes, so cache misses recur. Do not use
   an admin token. Store the user's token as a pull secret:

   ```console
   kubectl -n jupiterone create secret docker-registry artifactory-pull \
     --docker-server=<artifactory-host> \
     --docker-username=jupiterone-puller \
     --docker-password=<token>
   ```

3. Install with these values:

   ```yaml
   controllerManager:
     container:
       image:
         repository: <artifactory-host>/ecr-public/jupiterone/jupiterone-integration-operator
     imageRegistry: <artifactory-host>/ecr-public
     imagePullSecrets:
       - name: artifactory-pull
   ```

As with Harbor, the TLS certificate must chain to a public CA.

#### Mirror egress for Harbor and Artifactory

A Harbor or Artifactory mirror fetches from Public ECR itself, so the mirror
host, not the cluster, needs egress to `public.ecr.aws:443` and to the
CloudFront host that `public.ecr.aws` redirects image layer downloads to. AWS
does not document that hostname and can change it, so confirm it from the
mirror's own logs and monitor it rather than allowlisting a fixed name.

On AWS you can avoid that egress by chaining the mirror to an
[ECR pull-through cache](#aws-ecr-pull-through-cache): point the Harbor
endpoint (provider `AWS ECR`) or the Artifactory remote at
`https://<account>.dkr.ecr.<region>.amazonaws.com`, with credentials that have
the permissions in step 3 of that section, and add the cache prefix to `imageRegistry` (for example
`<harbor-host>/<project>/jupiterone-public`).

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

### Common labels and annotations

`commonLabels` and `commonAnnotations` are set on every object this chart
creates, directly or indirectly (requires operator v0.6.0, chart 1.6.0 or
later):

- every rendered resource, including the CRDs, the operator pod, and with
  `certmanager.enable` the metrics certificate Secret
- the operator's leader-election Lease (labels only, not annotations)
- every object the operator creates for integration runs: runner auth Secret,
  run Secret, `IntegrationInstanceJob`, job Secret, Job and pod

```yaml
commonLabels:
  team: security
  cost-center: "1234"   # quote numeric values
commonAnnotations:
  owner: platform
```

- More specific values win on the same key: `controllerManager.deployment.*`,
  `controllerManager.pod.*`, the ServiceAccount `annotations`, and
  `controllerManager.job.*` for runs. The runner and integration charts have
  their own `commonLabels`, which win over these for their runs.
- Label keys the chart sets (`app.kubernetes.io/name`, `instance`, `version`,
  `managed-by`, `helm.sh/chart`, `control-plane`) are skipped everywhere,
  including the Lease and run objects.
- Keys the operator manages on run objects (`log-watcher`, `job-name`,
  `controller-uid`, `batch.kubernetes.io/*`, `integrations.jupiterone.io/*`)
  are set on the chart's resources but not on run objects.
- `helm.sh/*` and `meta.helm.sh/*` annotations are skipped everywhere, as is
  `kubectl.kubernetes.io/default-container` (the chart sets it on the manager
  pod), in `commonAnnotations` and in the object-specific annotation values.
- Events are not labelled. Keys you remove stay on objects the operator
  already created.

### Job labels, annotations and scheduling

`controllerManager.job` applies to every integration run the operator launches
(requires operator v0.6.0, chart 1.6.0 or later):

```yaml
controllerManager:
  job:
    labels:                 # every object created for a run: runner auth
      team: security        # Secret, run Secret, IntegrationInstanceJob,
    annotations: {}         # job Secret and Job
    podLabels:              # the job pod
      cost-center: "1234"   # quote numeric values
    podAnnotations:
      sidecar.istio.io/inject: "false"
    nodeSelector:           # the job pod spec
      pool: tools
    tolerations:
      - key: dedicated
        operator: Equal
        value: tools
        effect: NoSchedule
    affinity: {}
    podSecurityContext: {}
    containerSecurityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
```

`commonLabels` and `commonAnnotations` are folded into these (`labels` and
`podLabels`, `annotations` and `podAnnotations`); `controllerManager.job` wins
on the same key.

The runner chart's `commonLabels` and `commonAnnotations` win over these for
that runner's runs. Integration charts add per-instance `commonLabels`,
`jobLabels`, `jobAnnotations`, `podLabels` and `podAnnotations`, which win
over both and go on the run Secret, `IntegrationInstanceJob`, job Secret, Job
and pod. They apply to the next run and only to instances created from an
`IntegrationInstance` resource.

- Keys the operator manages are rejected in `controllerManager.job`: `app.kubernetes.io/name`,
  `log-watcher`, `job-name`, `controller-uid`, `batch.kubernetes.io/*`,
  `integrations.jupiterone.io/*`.
- An invalid label, annotation or `nodeSelector` entry, or a scheduling or
  security field the API server's validation rejects (checked with a dry-run
  Job; a denial by an admission policy or webhook is only logged), stops the new operator pod at
  startup while the previous one keeps running. Check `kubectl rollout status` after `helm upgrade`; without
  `--wait`, Helm reports success either way.
- Quote numeric values: Helm reads unquoted numbers as floats, so `1.0` becomes
  `"1"` and large numbers use exponent notation.
- Integration images run as root, so a Pod Security `restricted` namespace is
  not supported yet.
- `controllerManager.nodeSelector`, `tolerations` and `affinity` schedule the
  operator pod itself; set both when nodes are tainted.

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
- **`Image verification failed against custom registry, falling back to ghcr.io`:**
  the operator could not verify against `imageRegistry`. A `401 Unauthorized`
  means `controllerManager.imagePullSecrets` is missing or the token expired. See
  [Private registry mirror](#private-registry-mirror).
- **`failed to get trusted root`:** allow egress to `tuf-repo-cdn.sigstore.dev:443`.
- **`authorization token has expired` from cosign when testing by hand:** a
  stale `public.ecr.aws` entry in `~/.docker/config.json` stops cosign from
  pulling anonymously. Run `docker logout public.ecr.aws` and retry.
- **Job pod `ErrImagePull` with `NotFound` from an ECR pull-through cache:** the
  node role lacks `ecr:CreateRepository` or `ecr:BatchImportUpstreamImage` on the
  cache prefix.

## Support

If you need help, please contact JupiterOne support
