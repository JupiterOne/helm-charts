package regression

import (
	"fmt"
	"path/filepath"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/helm"
	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/retry"
)

// Subtests share cluster-scoped names (CRDs, ClusterRoles), so they run sequentially.
func TestOperatorChart(t *testing.T) {
	local := localChart(t)
	helmHome := t.TempDir()
	t.Logf("working tree chart %s appVersion %s", local.Version, local.AppVersion)

	t.Run("FreshInstallWithDefaults", func(t *testing.T) {
		opts := kubectlOptions(t, namespace)
		release := "regression-fresh"
		withNamespace(t, opts)
		uninstallOnCleanup(t, opts, helmHome, release)

		helm.Install(t, helmOptions(opts, helmHome, nil), chartDir(t), release)
		assertCRDsEstablished(t, opts)
		assertManagerHealthy(t, opts, local.AppVersion)

		helm.Delete(t, helmOptions(opts, helmHome, nil), release, true)
		assertReleaseResourcesGone(t, opts, release)
		waitForCRDsGone(t, opts)
	})

	t.Run("UpgradeFromPreviousPublishedChart", func(t *testing.T) {
		opts := kubectlOptions(t, namespace)
		release := "regression-upgrade"
		previous := previousPublishedChart(t, local.Version)
		t.Logf("upgrading from published chart %s appVersion %s", previous.Version, previous.AppVersion)
		withNamespace(t, opts)
		uninstallOnCleanup(t, opts, helmHome, release)

		helm.Install(t, helmOptions(opts, helmHome, nil), previous.URLs[0], release)
		assertCRDsEstablished(t, opts)
		k8s.WaitUntilDeploymentAvailable(t, opts, deploymentName, 60, 5*time.Second)
		assertManagerImage(t, opts, previous.AppVersion)

		helm.Upgrade(t, helmOptions(opts, helmHome, nil), chartDir(t), release)
		assertCRDsEstablished(t, opts)
		assertChartLabel(t, opts, local.Version)
		assertManagerHealthy(t, opts, local.AppVersion)

		helm.Delete(t, helmOptions(opts, helmHome, nil), release, true)
		assertReleaseResourcesGone(t, opts, release)
		waitForCRDsGone(t, opts)
	})

	t.Run("UninstallKeepsCRDsWhenCRDKeepIsSet", func(t *testing.T) {
		opts := kubectlOptions(t, namespace)
		release := "regression-crd-keep"
		withNamespace(t, opts)
		uninstallOnCleanup(t, opts, helmHome, release)
		t.Cleanup(func() {
			for _, crd := range operatorCRDs {
				k8s.RunKubectl(t, opts, "delete", "crd", crd, "--ignore-not-found")
			}
		})

		values := map[string]string{"crd.keep": "true"}
		helm.Install(t, helmOptions(opts, helmHome, values), chartDir(t), release)
		assertCRDsEstablished(t, opts)
		k8s.WaitUntilDeploymentAvailable(t, opts, deploymentName, 60, 5*time.Second)

		helm.Delete(t, helmOptions(opts, helmHome, values), release, true)
		assertReleaseResourcesGone(t, opts, release)
		for _, crd := range operatorCRDs {
			if !crdExists(t, opts, crd) {
				t.Fatalf("crd %s was deleted although crd.keep=true", crd)
			}
		}
	})
}

// helmOptions isolates helm config and cache from the developer's own repositories.
func helmOptions(opts *k8s.KubectlOptions, helmHome string, values map[string]string) *helm.Options {
	wait := []string{"--wait", "--timeout", "5m"}
	return &helm.Options{
		KubectlOptions: opts,
		SetValues:      values,
		EnvVars: map[string]string{
			"HELM_CONFIG_HOME": filepath.Join(helmHome, "config"),
			"HELM_CACHE_HOME":  filepath.Join(helmHome, "cache"),
			"HELM_DATA_HOME":   filepath.Join(helmHome, "data"),
		},
		ExtraArgs: map[string][]string{
			"install": wait,
			"upgrade": wait,
			"delete":  wait,
		},
	}
}

func uninstallOnCleanup(t *testing.T, opts *k8s.KubectlOptions, helmHome, release string) {
	t.Helper()
	t.Cleanup(func() {
		if !t.Failed() {
			return
		}
		if err := helm.DeleteE(t, helmOptions(opts, helmHome, nil), release, true); err != nil {
			t.Logf("cleanup: uninstalling %s: %v", release, err)
		}
	})
}

func withNamespace(t *testing.T, opts *k8s.KubectlOptions) {
	t.Helper()
	k8s.CreateNamespace(t, opts, opts.Namespace)
	t.Cleanup(func() {
		k8s.RunKubectl(t, opts, "delete", "namespace", opts.Namespace, "--ignore-not-found", "--wait", "--timeout=120s")
	})
}

func assertChartLabel(t *testing.T, opts *k8s.KubectlOptions, version string) {
	t.Helper()
	retry.DoWithRetry(t, "deployment carries upgraded chart label", 12, 5*time.Second, func() (string, error) {
		got := k8s.GetDeployment(t, opts, deploymentName).Labels["helm.sh/chart"]
		if got != version {
			return "", fmt.Errorf("helm.sh/chart = %q, want %q", got, version)
		}
		return got, nil
	})
}
