#!/usr/bin/env bash

semver_parse() {
  local raw="${1#v}"
  raw="${raw%%+*}"
  local core="${raw%%-*}" pre=""
  if [ "$core" != "$raw" ]; then
    pre="${raw#*-}"
  fi
  if [[ ! "$core" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "ERROR: '$1' is not a semantic version" >&2
    return 1
  fi
  echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${pre}"
}

semver_compare() {
  local a b
  a=$(semver_parse "$1") || return 1
  b=$(semver_parse "$2") || return 1
  local a_core b_core a_pre b_pre i
  read -r -a a_core <<<"$a"
  read -r -a b_core <<<"$b"
  a_pre="${a_core[3]:-}"
  b_pre="${b_core[3]:-}"
  for i in 0 1 2; do
    if ((10#${a_core[i]} != 10#${b_core[i]})); then
      ((10#${a_core[i]} > 10#${b_core[i]})) && echo 1 || echo -1
      return 0
    fi
  done
  if [ "$a_pre" = "$b_pre" ]; then
    echo 0
  elif [ -z "$a_pre" ]; then
    echo 1
  elif [ -z "$b_pre" ]; then
    echo -1
  elif [ "$(printf '%s\n%s\n' "$a_pre" "$b_pre" | sort -V | tail -n1)" = "$a_pre" ]; then
    echo 1
  else
    echo -1
  fi
}

semver_change_level() {
  local a b
  a=$(semver_parse "$1") || return 1
  b=$(semver_parse "$2") || return 1
  local a_major a_minor b_major b_minor
  read -r a_major a_minor _ <<<"$a"
  read -r b_major b_minor _ <<<"$b"
  if ((10#$a_major != 10#$b_major)); then
    echo major
  elif ((10#$a_minor != 10#$b_minor)); then
    echo minor
  else
    echo patch
  fi
}

semver_bump() {
  local parsed
  parsed=$(semver_parse "$1") || return 1
  local major minor patch _
  read -r major minor patch _ <<<"$parsed"
  case "$2" in
    major) echo "$((10#$major + 1)).0.0" ;;
    minor) echo "$((10#$major)).$((10#$minor + 1)).0" ;;
    patch) echo "$((10#$major)).$((10#$minor)).$((10#$patch + 1))" ;;
    *)
      echo "ERROR: unknown bump level '$2'" >&2
      return 1
      ;;
  esac
}
