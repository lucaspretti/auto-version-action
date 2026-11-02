#!/usr/bin/env bash
# version-utils.sh
# Shared functions for reading and writing version from various file formats.
# Sourced by analyze-commits.sh and bump-version.sh.

# detect_version_file_type <filepath>
# Outputs: json, toml, yaml, plain
detect_version_file_type() {
  local file="$1"
  local basename
  basename=$(basename "$file")

  case "$basename" in
    package.json|composer.json|*.json) echo "json" ;;
    pyproject.toml|*.toml)             echo "toml" ;;
    Chart.yaml|*.yaml|*.yml)           echo "yaml" ;;
    VERSION|VERSION.txt)               echo "plain" ;;
    *)
      echo "ERROR: unsupported version file: $basename" >&2
      return 1
      ;;
  esac
}

# read_version <filepath>
# Outputs the version string to stdout.
read_version() {
  local file="$1"
  local type
  type=$(detect_version_file_type "$file")

  case "$type" in
    json)
      jq -r '.version' "$file"
      ;;
    toml)
      grep -m1 '^version[[:space:]]*=' "$file" | sed 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/'
      ;;
    yaml)
      grep -m1 '^version:' "$file" | sed 's/^version:[[:space:]]*//' | sed 's/^["'"'"']//' | sed 's/["'"'"']$//'
      ;;
    plain)
      tr -d '[:space:]' < "$file"
      ;;
  esac
}

# _write_via_tmp <filepath> <command...>
# Runs command with output to a temp file, then atomically replaces the target.
# Cleans up temp file on failure.
_write_via_tmp() {
  local file="$1"; shift
  local tmp
  tmp=$(mktemp)
  if "$@" > "$tmp"; then
    mv "$tmp" "$file"
  else
    rm -f "$tmp"
    return 1
  fi
}

# write_version <filepath> <new_version>
# Updates the version in-place.
write_version() {
  local file="$1"
  local version="$2"
  local type
  type=$(detect_version_file_type "$file")

  case "$type" in
    json)
      _write_via_tmp "$file" jq --arg v "$version" '.version = $v' "$file"
      ;;
    toml)
      _write_via_tmp "$file" sed "s/^version[[:space:]]*=.*/version = \"$version\"/" "$file"
      ;;
    yaml)
      _write_via_tmp "$file" sed "s/^version:.*/version: \"$version\"/" "$file"
      ;;
    plain)
      printf '%s\n' "$version" > "$file"
      ;;
  esac
}

# last_release_tag [below_version]
# Outputs the highest final release tag (vX.Y.Z, no pre-release) in the repo, or
# nothing when there is none. With below_version, only tags strictly lower count.
# Deliberately NOT `git describe`: describe only sees tags reachable from HEAD, and
# in a develop -> staging -> master flow the release tags live on master. A branch
# that does not contain the release commit (develop, or a staging branch recreated
# after auto-delete-on-merge) would otherwise compute from a stale baseline and
# produce a lower version, or an RC of a version that was already released.
last_release_tag() {
  local below="${1:-}"
  git tag -l 'v*' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | sed 's/^v//' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | awk -v below="$below" -F. '
        BEGIN { if (below != "") split(below, b, ".") }
        below == "" { print; next }
        ($1 < b[1]) || ($1 == b[1] && $2 < b[2]) || ($1 == b[1] && $2 == b[2] && $3 < b[3]) { print }
      ' \
    | tail -1 \
    | sed 's/^/v/' \
    | grep . || true
}
