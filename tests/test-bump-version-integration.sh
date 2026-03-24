#!/usr/bin/env bash
set -euo pipefail

# test-bump-version-integration.sh
# Integration tests for bump-version.sh production control flow.
# Uses a temporary git repo to test single-branch vs two-branch mode paths.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

ORIGINAL_DIR="$PWD"

echo "=== bump-version.sh integration (production paths) ==="

# --- Setup helpers ---

setup_test_repo() {
  local tmpdir
  tmpdir=$(mktemp -d)
  cd "$tmpdir"
  git init -q
  git config user.name "test"
  git config user.email "test@test.com"

  # Create version-utils.sh (needed by bump-version.sh)
  mkdir -p scripts
  cp "$SCRIPT_DIR/../scripts/version-utils.sh" scripts/

  # Create VERSION file
  echo "1.5.6" > VERSION
  git add -A
  git commit -q -m "initial commit"

  # Set up a bare remote so push/pull don't fail
  local bare
  bare=$(mktemp -d)
  git init -q --bare "$bare"
  git remote add origin "$bare"
  git push -q origin master 2>/dev/null || git push -q origin main 2>/dev/null || true

  echo "$tmpdir"
}

cleanup_test_repo() {
  cd "$ORIGINAL_DIR"
  rm -rf "$1"
}

# Run bump-version.sh capturing GITHUB_OUTPUT content
run_bump() {
  local bump_type="$1"
  local staging_branch="${2:-staging}"
  local production_branch="${3:-master}"

  local output_file
  output_file=$(mktemp)

  # Determine the default branch name in this repo
  local branch_name
  branch_name=$(git branch --show-current)

  GITHUB_OUTPUT="$output_file" \
  GITHUB_REF="refs/heads/$branch_name" \
  INPUT_VERSION_FILE="VERSION" \
  INPUT_HELM_CHART="" \
  INPUT_STAGING_BRANCH="$staging_branch" \
  INPUT_PRODUCTION_BRANCH="$branch_name" \
  BUMP_TYPE="$bump_type" \
  IS_SUBSEQUENT_RC="false" \
  bash "$SCRIPT_DIR/../scripts/bump-version.sh" 2>&1 || true

  cat "$output_file"
  rm -f "$output_file"
}

# --- Tests ---

# Test 1: Single-branch mode bumps even when tag exists
TMPDIR=$(setup_test_repo)
cd "$TMPDIR"
git tag -a "v1.5.6" -m "v1.5.6"

test_start "single-branch: bumps to 1.5.7 when v1.5.6 tag exists"
OUTPUT=$(run_bump "patch")
VERSION_LINE=$(echo "$OUTPUT" | grep "^version=" | head -1)
assert_eq "version=1.5.7" "$VERSION_LINE" "version should bump to 1.5.7"

test_start "single-branch: version_changed=true after bump"
CHANGED_LINE=$(echo "$OUTPUT" | grep "^version_changed=" | head -1)
assert_eq "version_changed=true" "$CHANGED_LINE" "version_changed should be true"
cleanup_test_repo "$TMPDIR"

# Test 2: Single-branch mode minor bump
TMPDIR=$(setup_test_repo)
cd "$TMPDIR"
git tag -a "v1.5.6" -m "v1.5.6"

test_start "single-branch: minor bump from 1.5.6 to 1.6.0"
OUTPUT=$(run_bump "minor")
VERSION_LINE=$(echo "$OUTPUT" | grep "^version=" | head -1)
assert_eq "version=1.6.0" "$VERSION_LINE" "version should bump to 1.6.0"
cleanup_test_repo "$TMPDIR"

# Test 3: Single-branch mode major bump
TMPDIR=$(setup_test_repo)
cd "$TMPDIR"
git tag -a "v1.5.6" -m "v1.5.6"

test_start "single-branch: major bump from 1.5.6 to 2.0.0"
OUTPUT=$(run_bump "major")
VERSION_LINE=$(echo "$OUTPUT" | grep "^version=" | head -1)
assert_eq "version=2.0.0" "$VERSION_LINE" "version should bump to 2.0.0"
cleanup_test_repo "$TMPDIR"

# Test 4: Single-branch mode skips when version already correct
TMPDIR=$(setup_test_repo)
cd "$TMPDIR"
echo "1.6.0" > VERSION
git add VERSION
git commit -q -m "already bumped"
git push -q origin HEAD 2>/dev/null || true
git tag -a "v1.5.6" -m "v1.5.6" HEAD~1

test_start "single-branch: skips bump when version already >= expected"
OUTPUT=$(run_bump "minor")
VERSION_LINE=$(echo "$OUTPUT" | grep "^version=" | head -1)
assert_eq "version=1.6.0" "$VERSION_LINE" "version stays at 1.6.0"

test_start "single-branch: version_changed=false when already correct"
CHANGED_LINE=$(echo "$OUTPUT" | grep "^version_changed=" | head -1)
assert_eq "version_changed=false" "$CHANGED_LINE" "no change needed"
cleanup_test_repo "$TMPDIR"

# Test 5: type=none skips entirely
TMPDIR=$(setup_test_repo)
cd "$TMPDIR"

test_start "production: type=none skips entirely"
OUTPUT=$(run_bump "none")
VERSION_LINE=$(echo "$OUTPUT" | grep "^version=" | head -1)
assert_eq "version=1.5.6" "$VERSION_LINE" "version unchanged"

test_start "production: type=none sets version_changed=false"
CHANGED_LINE=$(echo "$OUTPUT" | grep "^version_changed=" | head -1)
assert_eq "version_changed=false" "$CHANGED_LINE"
cleanup_test_repo "$TMPDIR"

# Test 6: Single-branch first release (no previous tag)
TMPDIR=$(setup_test_repo)
cd "$TMPDIR"
echo "0.0.0" > VERSION
git add VERSION
git commit -q -m "reset version"
git push -q origin HEAD 2>/dev/null || true

test_start "single-branch: first release bumps from 0.0.0 to 0.1.0"
OUTPUT=$(run_bump "minor")
VERSION_LINE=$(echo "$OUTPUT" | grep "^version=" | head -1)
assert_eq "version=0.1.0" "$VERSION_LINE" "first minor release"
cleanup_test_repo "$TMPDIR"

# --- Summary ---
test_summary "bump-version integration"
