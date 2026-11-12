#!/usr/bin/env bash
# Bumps the jupiterone-integration-operator chart to an operator release.
# Usage: VERSION=X.Y.Z scripts/bump-operator-chart.sh
# Writes changed, tag, chart_version and previous_tag to $GITHUB_OUTPUT when set.
set -euo pipefail

CHART_FILE="charts/jupiterone-integration-operator/Chart.yaml"
OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

if [ ! -f "$CHART_FILE" ]; then
  echo "ERROR: run from the repository root; $CHART_FILE not found" >&2
  exit 1
fi

if [[ ! "${VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: VERSION must match X.Y.Z (got '${VERSION:-}')" >&2
  exit 1
fi

TAG="v${VERSION}"
current_tag=$(sed -n -E 's/^appVersion:[[:space:]]*"?([^"]+)"?[[:space:]]*$/\1/p' "$CHART_FILE")
current_chart=$(sed -n -E 's/^version:[[:space:]]*"?([0-9]+\.[0-9]+\.[0-9]+)"?[[:space:]]*$/\1/p' "$CHART_FILE")

if [[ ! "$current_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ ! "$current_chart" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: could not parse version/appVersion from $CHART_FILE (version='$current_chart', appVersion='$current_tag')" >&2
  exit 1
fi

{
  echo "tag=$TAG"
  echo "previous_tag=$current_tag"
} >>"$OUTPUT"

if [ "$current_tag" = "$TAG" ]; then
  echo "Chart appVersion is already $TAG; nothing to do."
  echo "changed=false" >>"$OUTPUT"
  exit 0
fi

newest=$(printf '%s\n%s\n' "${current_tag#v}" "$VERSION" | sort -V | tail -n1)
if [ "$newest" != "$VERSION" ]; then
  echo "Operator $TAG is older than chart appVersion $current_tag; refusing to downgrade."
  echo "changed=false" >>"$OUTPUT"
  exit 0
fi

IFS=. read -r major minor patch <<<"$current_chart"
chart_version="${major}.${minor}.$((patch + 1))"

CHART_VERSION="$chart_version" APP_VERSION="$TAG" perl -pi -e '
  s/^version:.*$/version: $ENV{CHART_VERSION}/;
  s/^appVersion:.*$/appVersion: "$ENV{APP_VERSION}"/;
' "$CHART_FILE"

make sync-crds OPERATOR_TAG="$TAG"

echo "Bumped chart $current_chart -> $chart_version, appVersion $current_tag -> $TAG"
{
  echo "changed=true"
  echo "chart_version=$chart_version"
} >>"$OUTPUT"
