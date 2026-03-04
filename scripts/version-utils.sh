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
