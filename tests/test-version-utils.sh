#!/usr/bin/env bash
set -euo pipefail

# test-version-utils.sh
# Tests for scripts/version-utils.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"
source "$SCRIPT_DIR/../scripts/version-utils.sh"

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

echo "=== version-utils.sh ==="

# --- detect_version_file_type ---

test_start "detect_version_file_type: package.json"
assert_eq "json" "$(detect_version_file_type "package.json")"

test_start "detect_version_file_type: composer.json"
assert_eq "json" "$(detect_version_file_type "composer.json")"

test_start "detect_version_file_type: custom.json"
assert_eq "json" "$(detect_version_file_type "custom.json")"

test_start "detect_version_file_type: pyproject.toml"
assert_eq "toml" "$(detect_version_file_type "pyproject.toml")"

test_start "detect_version_file_type: custom.toml"
assert_eq "toml" "$(detect_version_file_type "custom.toml")"

test_start "detect_version_file_type: Chart.yaml"
assert_eq "yaml" "$(detect_version_file_type "Chart.yaml")"

test_start "detect_version_file_type: custom.yml"
assert_eq "yaml" "$(detect_version_file_type "custom.yml")"

test_start "detect_version_file_type: VERSION"
assert_eq "plain" "$(detect_version_file_type "VERSION")"

test_start "detect_version_file_type: VERSION.txt"
assert_eq "plain" "$(detect_version_file_type "VERSION.txt")"

test_start "detect_version_file_type: unsupported file"
if detect_version_file_type "Makefile" 2>/dev/null; then
  assert_unexpected "should have failed"
else
  assert_true "returns error for unsupported"
fi

# --- read_version / write_version: plain ---

test_start "read/write: plain VERSION"
echo "1.2.3" > "$TMPDIR_TEST/VERSION"
assert_eq "1.2.3" "$(read_version "$TMPDIR_TEST/VERSION")"

test_start "write then read: plain VERSION"
write_version "$TMPDIR_TEST/VERSION" "4.5.6"
assert_eq "4.5.6" "$(read_version "$TMPDIR_TEST/VERSION")"

# --- read_version / write_version: JSON ---

test_start "read: JSON package.json"
echo '{"name":"test","version":"2.0.0"}' > "$TMPDIR_TEST/package.json"
assert_eq "2.0.0" "$(read_version "$TMPDIR_TEST/package.json")"

test_start "write then read: JSON package.json"
write_version "$TMPDIR_TEST/package.json" "3.1.0"
assert_eq "3.1.0" "$(read_version "$TMPDIR_TEST/package.json")"

# --- read_version / write_version: TOML ---

test_start "read: TOML pyproject.toml"
cat > "$TMPDIR_TEST/pyproject.toml" <<'TOML'
[project]
name = "myapp"
version = "0.5.0"
TOML
assert_eq "0.5.0" "$(read_version "$TMPDIR_TEST/pyproject.toml")"

test_start "write then read: TOML pyproject.toml"
write_version "$TMPDIR_TEST/pyproject.toml" "1.0.0"
assert_eq "1.0.0" "$(read_version "$TMPDIR_TEST/pyproject.toml")"

# --- read_version / write_version: YAML ---

test_start "read: YAML Chart.yaml"
cat > "$TMPDIR_TEST/Chart.yaml" <<'YAML'
apiVersion: v2
name: mychart
version: "0.3.0"
appVersion: "0.3.0"
YAML
assert_eq "0.3.0" "$(read_version "$TMPDIR_TEST/Chart.yaml")"

test_start "write then read: YAML Chart.yaml"
write_version "$TMPDIR_TEST/Chart.yaml" "2.0.0"
assert_eq "2.0.0" "$(read_version "$TMPDIR_TEST/Chart.yaml")"

test_start "read: YAML without quotes"
cat > "$TMPDIR_TEST/Chart.yaml" <<'YAML'
apiVersion: v2
name: mychart
version: 1.5.0
YAML
assert_eq "1.5.0" "$(read_version "$TMPDIR_TEST/Chart.yaml")"

# --- Summary ---
test_summary "version-utils"
