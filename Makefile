# Helm Charts Makefile

OPERATOR_REPO := JupiterOne/jupiterone-integration-operator
OPERATOR_CRD_DIR := charts/jupiterone-integration-operator/templates/crds
OPERATOR_TAG ?=
REGRESSION_CLUSTER ?= helm-charts-regression
REGRESSION_KUBECONFIG ?= $(CURDIR)/.regression-kubeconfig

.PHONY: help
help: ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Sync

.PHONY: sync-crds
sync-crds: ## Sync CRDs from an operator release (OPERATOR_TAG=vX.Y.Z, default latest tag)
	@TAG="$(OPERATOR_TAG)" && \
	if [ -z "$$TAG" ]; then \
		echo "Fetching latest tag from $(OPERATOR_REPO)..." && \
		TAG=$$(gh api repos/$(OPERATOR_REPO)/tags --jq '.[0].name'); \
	fi && \
	echo "Operator tag: $$TAG" && \
	echo "Downloading source archive..." && \
	gh api repos/$(OPERATOR_REPO)/tarball/$${TAG} > operator.tar.gz && \
	mkdir -p _operator_src && \
	tar xzf operator.tar.gz -C _operator_src && \
	echo "Syncing CRDs to $(OPERATOR_CRD_DIR)..." && \
	for f in _operator_src/*/config/crd/bases/*.yaml; do \
		sed '1{/^---$$/d;}' "$$f" | awk ' \
			/^metadata:$$/ && !meta { print; \
				print "  {{- with (include \"chart.userLabels\" (dict \"ctx\" .) | trim) }}"; \
				print "  labels:"; \
				print "    {{- . | nindent 4 }}"; \
				print "  {{- end }}"; \
				meta=1; next } \
			/^  annotations:$$/ && !ann { print; \
				print "    {{- if .Values.crd.keep }}"; \
				print "    \"helm.sh/resource-policy\": keep"; \
				print "    {{- end }}"; \
				print "    {{- with (include \"chart.userAnnotations\" (dict \"ctx\" . \"skipPrefix\" \"controller-gen.kubebuilder.io/\") | trim) }}{{ . | nindent 4 }}{{ end }}"; \
				ann=1; next } \
			{ print }' > "$(OPERATOR_CRD_DIR)/$$(basename $$f)"; \
		echo "  Synced $$(basename $$f)"; \
	done && \
	rm -rf _operator_src operator.tar.gz && \
	echo "Done."

.PHONY: verify-crds
verify-crds: sync-crds ## Verify CRDs are in sync with the latest operator release (fails if changes detected)
	@if [ -n "$$(git status --porcelain $(OPERATOR_CRD_DIR))" ]; then \
		echo ""; \
		echo "ERROR: CRDs are out of sync with the latest operator release."; \
		echo ""; \
		echo "Changed files:"; \
		git status --porcelain $(OPERATOR_CRD_DIR); \
		echo ""; \
		echo "Run 'make sync-crds' locally and commit the changes."; \
		exit 1; \
	fi
	@echo "CRDs are in sync with the latest operator release."

##@ Test

.PHONY: test-regression
test-regression: ## Run the Terratest regression suite against a fresh, disposable kind cluster
	kind delete cluster --name '$(REGRESSION_CLUSTER)' --kubeconfig '$(REGRESSION_KUBECONFIG)'
	kind create cluster --name '$(REGRESSION_CLUSTER)' --kubeconfig '$(REGRESSION_KUBECONFIG)' --wait 120s
	cd test/regression && \
		REGRESSION_KUBECONFIG='$(REGRESSION_KUBECONFIG)' \
		REGRESSION_KUBE_CONTEXT='kind-$(REGRESSION_CLUSTER)' \
		go test -v -count=1 -timeout 30m ./...

.PHONY: test-regression-cleanup
test-regression-cleanup: ## Delete the regression kind cluster
	kind delete cluster --name '$(REGRESSION_CLUSTER)' --kubeconfig '$(REGRESSION_KUBECONFIG)'
