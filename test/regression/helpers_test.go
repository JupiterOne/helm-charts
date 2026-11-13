package regression

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Masterminds/semver/v3"
	http_helper "github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/retry"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/yaml"
)

const (
	chartName         = "jupiterone-integration-operator"
	chartRepoIndexURL = "https://jupiterone.github.io/helm-charts/index.yaml"
	namespace         = "jupiterone"
	deploymentName    = "jupiterone-integration-operator-controller-manager"
	managerLabel      = "control-plane=controller-manager"
	imageRepository   = "ghcr.io/jupiterone/jupiterone-integration-operator"
	healthProbePort   = 8081
)

var operatorCRDs = []string{
	"integrationinstancejobs.integrations.jupiterone.io",
	"integrationinstances.integrations.jupiterone.io",
	"integrationrunners.integrations.jupiterone.io",
}

type chartMetadata struct {
	Version    string `json:"version"`
	AppVersion string `json:"appVersion"`
}

type indexEntry struct {
	chartMetadata
	URLs []string `json:"urls"`
}

type repoIndex struct {
	Entries map[string][]indexEntry `json:"entries"`
}

func chartDir(t *testing.T) string {
	t.Helper()
	dir, err := filepath.Abs(filepath.Join("..", "..", "charts", chartName))
	if err != nil {
		t.Fatalf("resolving chart directory: %v", err)
	}
	return dir
}

func localChart(t *testing.T) chartMetadata {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join(chartDir(t), "Chart.yaml"))
	if err != nil {
		t.Fatalf("reading Chart.yaml: %v", err)
	}
	var meta chartMetadata
	if err := yaml.Unmarshal(raw, &meta); err != nil {
		t.Fatalf("parsing Chart.yaml: %v", err)
	}
	return meta
}

// kubectlOptions refuses to run against anything but an explicitly named kind cluster.
func kubectlOptions(t *testing.T, ns string) *k8s.KubectlOptions {
	t.Helper()
	kubeconfig := os.Getenv("REGRESSION_KUBECONFIG")
	kubeContext := os.Getenv("REGRESSION_KUBE_CONTEXT")
	if kubeconfig == "" || kubeContext == "" {
		t.Fatal("REGRESSION_KUBECONFIG and REGRESSION_KUBE_CONTEXT must be set; run `make test-regression` to create a disposable kind cluster")
	}
	if !strings.HasPrefix(kubeContext, "kind-") {
		t.Fatalf("REGRESSION_KUBE_CONTEXT %q is not a kind cluster; the regression suite only runs against disposable kind clusters", kubeContext)
	}
	return k8s.NewKubectlOptions(kubeContext, kubeconfig, ns)
}

func soakDuration(t *testing.T) time.Duration {
	t.Helper()
	raw := os.Getenv("REGRESSION_SOAK")
	if raw == "" {
		return 60 * time.Second
	}
	d, err := time.ParseDuration(raw)
	if err != nil {
		t.Fatalf("parsing REGRESSION_SOAK %q: %v", raw, err)
	}
	return d
}

// previousPublishedChart returns the newest published chart older than the working tree chart.
func previousPublishedChart(t *testing.T, current string) indexEntry {
	t.Helper()
	resp, err := http.Get(chartRepoIndexURL)
	if err != nil {
		t.Fatalf("fetching %s: %v", chartRepoIndexURL, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("fetching %s: HTTP %d", chartRepoIndexURL, resp.StatusCode)
	}
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("reading %s: %v", chartRepoIndexURL, err)
	}
	var index repoIndex
	if err := yaml.Unmarshal(raw, &index); err != nil {
		t.Fatalf("parsing %s: %v", chartRepoIndexURL, err)
	}

	currentVersion, err := semver.NewVersion(current)
	if err != nil {
		t.Fatalf("parsing working tree chart version %q: %v", current, err)
	}
	override := os.Getenv("REGRESSION_PREVIOUS_VERSION")
	var best *indexEntry
	var bestVersion *semver.Version
	for i, entry := range index.Entries[chartName] {
		v, err := semver.NewVersion(entry.Version)
		if err != nil || v.Prerelease() != "" || len(entry.URLs) == 0 {
			continue
		}
		if override != "" {
			if entry.Version == override {
				return index.Entries[chartName][i]
			}
			continue
		}
		if v.LessThan(currentVersion) && (bestVersion == nil || v.GreaterThan(bestVersion)) {
			best, bestVersion = &index.Entries[chartName][i], v
		}
	}
	if override != "" {
		t.Fatalf("REGRESSION_PREVIOUS_VERSION %s is not published in %s", override, chartRepoIndexURL)
	}
	if best == nil {
		t.Fatalf("no published %s chart older than %s in %s", chartName, current, chartRepoIndexURL)
	}
	return *best
}

// managerPods skips pods already terminating, such as the previous ReplicaSet's pod after an upgrade.
func managerPods(t *testing.T, opts *k8s.KubectlOptions) []corev1.Pod {
	t.Helper()
	var live []corev1.Pod
	for _, pod := range k8s.ListPods(t, opts, metav1.ListOptions{LabelSelector: managerLabel}) {
		if pod.DeletionTimestamp == nil {
			live = append(live, pod)
		}
	}
	return live
}

func assertCRDsEstablished(t *testing.T, opts *k8s.KubectlOptions) {
	t.Helper()
	for _, crd := range operatorCRDs {
		k8s.RunKubectl(t, opts, "wait", "--for=condition=Established", "--timeout=60s", "crd/"+crd)
	}
}

func assertManagerImage(t *testing.T, opts *k8s.KubectlOptions, appVersion string) {
	t.Helper()
	deployment := k8s.GetDeployment(t, opts, deploymentName)
	want := fmt.Sprintf("%s:%s", imageRepository, appVersion)
	for _, c := range deployment.Spec.Template.Spec.Containers {
		if c.Name == "manager" {
			if c.Image != want {
				t.Fatalf("manager image = %q, want %q", c.Image, want)
			}
			return
		}
	}
	t.Fatalf("deployment %s has no manager container", deploymentName)
}

func assertManagerHealthy(t *testing.T, opts *k8s.KubectlOptions, appVersion string) {
	t.Helper()
	k8s.WaitUntilDeploymentAvailable(t, opts, deploymentName, 60, 5*time.Second)
	k8s.RunKubectl(t, opts, "rollout", "status", "deployment/"+deploymentName, "--timeout=5m")
	assertManagerImage(t, opts, appVersion)
	assertProbesOK(t, opts)
	assertNoRestartsDuringSoak(t, opts)
}

func assertProbesOK(t *testing.T, opts *k8s.KubectlOptions) {
	t.Helper()
	tunnel := k8s.NewTunnel(opts, k8s.ResourceTypeDeployment, deploymentName, 0, healthProbePort)
	defer tunnel.Close()
	tunnel.ForwardPort(t)
	for _, path := range []string{"/healthz", "/readyz"} {
		url := fmt.Sprintf("http://%s%s", tunnel.Endpoint(), path)
		http_helper.HttpGetWithRetryWithCustomValidation(t, url, nil, 12, 5*time.Second,
			func(status int, _ string) bool { return status == http.StatusOK })
	}
}

func assertNoRestartsDuringSoak(t *testing.T, opts *k8s.KubectlOptions) {
	t.Helper()
	before := podNames(managerPods(t, opts))
	soak := soakDuration(t)
	t.Logf("soaking operator for %s", soak)
	time.Sleep(soak)

	after := managerPods(t, opts)
	if got := podNames(after); got != before {
		t.Fatalf("manager pods changed during soak: before %s, after %s", before, got)
	}
	for _, pod := range after {
		if !k8s.IsPodAvailable(&pod) {
			t.Fatalf("manager pod %s is not ready after soak", pod.Name)
		}
		for _, cs := range pod.Status.ContainerStatuses {
			if cs.RestartCount != 0 {
				t.Fatalf("container %s in pod %s restarted %d times", cs.Name, pod.Name, cs.RestartCount)
			}
		}
	}
}

func podNames(pods []corev1.Pod) string {
	names := make([]string, 0, len(pods))
	for _, p := range pods {
		names = append(names, p.Name)
	}
	return strings.Join(names, ",")
}

func crdExists(t *testing.T, opts *k8s.KubectlOptions, crd string) bool {
	t.Helper()
	out, err := k8s.RunKubectlAndGetOutputE(t, opts, "get", "crd", crd, "--ignore-not-found", "-o", "name")
	if err != nil {
		t.Fatalf("checking crd %s: %v", crd, err)
	}
	return strings.TrimSpace(out) != ""
}

func waitForCRDsGone(t *testing.T, opts *k8s.KubectlOptions) {
	t.Helper()
	retry.DoWithRetry(t, "CRDs removed", 24, 5*time.Second, func() (string, error) {
		for _, crd := range operatorCRDs {
			if crdExists(t, opts, crd) {
				return "", fmt.Errorf("crd %s still present", crd)
			}
		}
		return "removed", nil
	})
}

func assertReleaseResourcesGone(t *testing.T, opts *k8s.KubectlOptions, release string) {
	t.Helper()
	selector := "app.kubernetes.io/instance=" + release
	retry.DoWithRetry(t, "release resources removed", 24, 5*time.Second, func() (string, error) {
		out, err := k8s.RunKubectlAndGetOutputE(t, opts, "get",
			"deployment,service,serviceaccount,role,rolebinding,clusterrole,clusterrolebinding",
			"-A", "-l", selector, "-o", "name")
		if err != nil {
			return "", err
		}
		if strings.TrimSpace(out) != "" {
			return "", fmt.Errorf("resources still present for %s:\n%s", selector, out)
		}
		return "removed", nil
	})
}
