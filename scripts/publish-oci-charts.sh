#!/usr/bin/env bash
# Pushes every chart version not yet in the OCI destination; published versions are never overwritten.
set -euo pipefail

if [[ $# -ne 1 || "$1" != oci://* ]]; then
  echo "usage: $0 oci://<registry>/<namespace>" >&2
  exit 2
fi
destination="$1"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

published=0
skipped=0
for chart_yaml in "$repo_root"/charts/*/Chart.yaml; do
  chart_dir="$(dirname "$chart_yaml")"
  name="$(yq -r '.name' "$chart_yaml")"
  version="$(yq -r '.version' "$chart_yaml")"

  if helm show chart "$destination/$name" --version "$version" >/dev/null 2>&1; then
    echo "skip $name $version: already in $destination"
    skipped=$((skipped + 1))
    continue
  fi

  helm package "$chart_dir" --destination "$work_dir" >/dev/null
  helm push "$work_dir/$name-$version.tgz" "$destination"
  echo "published $name $version to $destination"
  published=$((published + 1))
done

echo "published=$published skipped=$skipped"
