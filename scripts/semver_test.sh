#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/lib/semver.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/semver.sh"

PASSED=0
FAILED=0

assert_eq() {
  local description="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $description"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $description (expected '$expected', got '$actual')"
    FAILED=$((FAILED + 1))
  fi
}

next_chart() {
  semver_bump "$3" "$(semver_change_level "$1" "$2")"
}

echo "=== chart version follows the operator change level ==="
assert_eq "patch: v0.7.4 -> 0.7.5 bumps chart 1.8.3 to 1.8.4" "1.8.4" "$(next_chart v0.7.4 0.7.5 1.8.3)"
assert_eq "minor: v0.7.4 -> 0.8.0 bumps chart 1.8.3 to 1.9.0" "1.9.0" "$(next_chart v0.7.4 0.8.0 1.8.3)"
assert_eq "major: v0.7.4 -> 1.0.0 bumps chart 1.8.3 to 2.0.0" "2.0.0" "$(next_chart v0.7.4 1.0.0 1.8.3)"
assert_eq "minor skip: v0.7.4 -> 0.9.2 bumps chart 1.8.3 to 1.9.0" "1.9.0" "$(next_chart v0.7.4 0.9.2 1.8.3)"
assert_eq "prerelease to release: v0.8.0-rc.1 -> 0.8.0 is a patch bump" "1.8.4" "$(next_chart v0.8.0-rc.1 0.8.0 1.8.3)"
assert_eq "prerelease chart version: 1.9.0-rc.1 minor bump drops suffix" "1.10.0" "$(next_chart v0.7.4 0.8.0 1.9.0-rc.1)"
assert_eq "build metadata ignored: v0.7.4+build.5 -> 0.7.5" "1.8.4" "$(next_chart v0.7.4+build.5 0.7.5 1.8.3)"

echo "=== comparison ==="
assert_eq "equal with and without v" "0" "$(semver_compare v0.7.4 0.7.4)"
assert_eq "newer patch" "1" "$(semver_compare v0.7.5 v0.7.4)"
assert_eq "older minor" "-1" "$(semver_compare v0.6.9 v0.7.0)"
assert_eq "numeric not lexical: 0.10.0 > 0.9.0" "1" "$(semver_compare 0.10.0 0.9.0)"
assert_eq "release beats its prerelease" "1" "$(semver_compare 0.8.0 v0.8.0-rc.1)"
assert_eq "prerelease below its release" "-1" "$(semver_compare v0.8.0-rc.1 0.8.0)"
assert_eq "rc.2 beats rc.1" "1" "$(semver_compare 0.8.0-rc.2 0.8.0-rc.1)"

echo "=== invalid input ==="
if semver_parse "latest" >/dev/null 2>&1; then
  assert_eq "rejects 'latest'" "error" "accepted"
else
  assert_eq "rejects 'latest'" "error" "error"
fi
if semver_parse "1.2" >/dev/null 2>&1; then
  assert_eq "rejects '1.2'" "error" "accepted"
else
  assert_eq "rejects '1.2'" "error" "error"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
