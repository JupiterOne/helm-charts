#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/lib/semver.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/semver.sh"

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
current_chart=$(sed -n -E 's/^version:[[:space:]]*"?([^"]+)"?[[:space:]]*$/\1/p' "$CHART_FILE")

if ! semver_parse "$current_tag" >/dev/null || ! semver_parse "$current_chart" >/dev/null; then
  echo "ERROR: could not parse version/appVersion from $CHART_FILE (version='$current_chart', appVersion='$current_tag')" >&2
  exit 1
fi

{
  echo "tag=$TAG"
  echo "previous_tag=$current_tag"
} >>"$OUTPUT"

case "$(semver_compare "$TAG" "$current_tag")" in
  0)
    echo "Chart appVersion is already $TAG; nothing to do."
    echo "changed=false" >>"$OUTPUT"
    exit 0
    ;;
  -1)
    echo "Operator $TAG is older than chart appVersion $current_tag; refusing to downgrade."
    echo "changed=false" >>"$OUTPUT"
    exit 0
    ;;
esac

level=$(semver_change_level "$current_tag" "$TAG")
chart_version=$(semver_bump "$current_chart" "$level")

CHART_VERSION="$chart_version" APP_VERSION="$TAG" perl -pi -e '
  s/^version:.*$/version: $ENV{CHART_VERSION}/;
  s/^appVersion:.*$/appVersion: "$ENV{APP_VERSION}"/;
' "$CHART_FILE"

make sync-crds OPERATOR_TAG="$TAG"

echo "Bumped chart $current_chart -> $chart_version ($level), appVersion $current_tag -> $TAG"
{
  echo "changed=true"
  echo "chart_version=$chart_version"
} >>"$OUTPUT"
