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

# Run bump-version.sh on an explicit branch, with explicit staging/production names
run_bump_on() {
  local bump_type="$1"
  local ref_branch="$2"
  local subsequent_rc="${3:-false}"

  local output_file
  output_file=$(mktemp)

  GITHUB_OUTPUT="$output_file" \
  GITHUB_REF="refs/heads/$ref_branch" \
  INPUT_VERSION_FILE="VERSION" \
  INPUT_HELM_CHART="" \
  INPUT_STAGING_BRANCH="staging" \
  INPUT_PRODUCTION_BRANCH="${PROD_BRANCH:-master}" \
  BUMP_TYPE="$bump_type" \
  IS_SUBSEQUENT_RC="$subsequent_rc" \
  bash "$SCRIPT_DIR/../scripts/bump-version.sh" 2>&1 || true

  cat "$output_file"
  rm -f "$output_file"
}

# Test 7: A branch that is neither staging nor production never mutates the version
TMPDIR=$(setup_test_repo)
cd "$TMPDIR"
git tag -a "v0.9.0" -m "v0.9.0"
echo "0.23.0" > VERSION
git commit -q -am "feat: work on develop"
git switch -q -c develop
HEAD_BEFORE=$(git rev-parse HEAD)

test_start "other branch: develop keeps its version"
OUTPUT=$(run_bump_on "minor" "develop")
VERSION_LINE=$(echo "$OUTPUT" | grep "^version=" | head -1)
assert_eq "version=0.23.0" "$VERSION_LINE" "develop must not be bumped"

test_start "other branch: version_changed=false and no RC"
CHANGED_LINE=$(echo "$OUTPUT" | grep "^version_changed=" | head -1)
RC_LINE=$(echo "$OUTPUT" | grep "^rc_version=" | head -1)
assert_eq "version_changed=false rc_version=" "$CHANGED_LINE $RC_LINE"

test_start "other branch: no bump commit created"
assert_eq "$HEAD_BEFORE" "$(git rev-parse HEAD)" "HEAD must not move"
cleanup_test_repo "$TMPDIR"

# Test 8: Staging recreated without the release commit (legal-text-delta, 2026-09).
# staging -> master released v0.23.0, auto-delete-on-merge removed staging, and it was
# restored from before the release commit. git describe on staging then saw v0.22.1,
# and the action cut v0.23.0-rc.4 of a version that was already final.
TMPDIR=$(setup_test_repo)
cd "$TMPDIR"
echo "0.22.1" > VERSION; git commit -q -am "chore: release 0.22.1"; git tag -a v0.22.1 -m v0.22.1
echo "0.23.0" > VERSION; git commit -q -am "feat: big feature"
git tag -a v0.23.0-rc.1 -m rc1; git tag -a v0.23.0-rc.3 -m rc3
git switch -q -c staging
git switch -q -
git commit -q --allow-empty -m "Merge pull request #2384 from web/staging"
git tag -a v0.23.0 -m v0.23.0
git switch -q staging
git commit -q --allow-empty -m "fix: handle guidelines TOC entries without labels"
git push -q origin staging 2>/dev/null || true

test_start "staging behind the release: never cuts an RC of a released version"
OUTPUT=$(run_bump_on "patch" "staging" "true")
RC_LINE=$(echo "$OUTPUT" | grep "^rc_version=" | head -1)
assert_eq "rc_version=0.23.1-rc.1" "$RC_LINE" "was 0.23.0-rc.4"

test_start "staging behind the release: version file moves to 0.23.1"
assert_eq "0.23.1" "$(cat VERSION)"
cleanup_test_repo "$TMPDIR"

# Test 8b: A version file set ahead by hand is never moved backwards
TMPDIR=$(setup_test_repo)
cd "$TMPDIR"
git tag -a "v1.5.6" -m "v1.5.6"
echo "2.0.0" > VERSION
git commit -q -am "fix: something"
git switch -q -c staging
git push -q origin staging 2>/dev/null || true
HEAD_BEFORE=$(git rev-parse HEAD)

test_start "staging: keeps a hand-set 2.0.0 instead of downgrading to 1.5.7"
OUTPUT=$(run_bump_on "patch" "staging")
RC_LINE=$(echo "$OUTPUT" | grep "^rc_version=" | head -1)
assert_eq "rc_version=2.0.0-rc.1" "$RC_LINE"

test_start "staging: no downgrade commit created"
assert_eq "$HEAD_BEFORE" "$(git rev-parse HEAD)" "HEAD must not move"
cleanup_test_repo "$TMPDIR"

# Test 9: Staging still bumps forward normally
TMPDIR=$(setup_test_repo)
cd "$TMPDIR"
git tag -a "v1.5.6" -m "v1.5.6"
git commit -q --allow-empty -m "feat: new thing"
git switch -q -c staging
git push -q origin staging 2>/dev/null || true

test_start "staging: minor bump from v1.5.6 to 1.6.0-rc.1"
OUTPUT=$(run_bump_on "minor" "staging")
RC_LINE=$(echo "$OUTPUT" | grep "^rc_version=" | head -1)
assert_eq "rc_version=1.6.0-rc.1" "$RC_LINE"
test_start "staging: VERSION file written"
assert_eq "1.6.0" "$(cat VERSION)"
cleanup_test_repo "$TMPDIR"

# Test 10: Two-branch mode, hotfix merged straight to production (dlms, dataDesk, legalTexts)
setup_two_branch_hotfix() {
  git switch -q -c staging; git push -q origin staging 2>/dev/null || true
  git switch -q master 2>/dev/null || git switch -q main
  echo "2.4.0" > VERSION; git commit -q -am "chore: release 2.4.0"
  git tag -a v2.4.0-rc.1 -m rc1; git tag -a v2.4.0 -m v2.4.0
}

TMPDIR=$(setup_test_repo)
cd "$TMPDIR"
setup_two_branch_hotfix
echo "2.4.1" > VERSION; git commit -q -am "fix: hotfix carrying its own version"
PROD=$(git branch --show-current)

test_start "hotfix to production: uses the version the hotfix branch carries"
OUTPUT=$(PROD_BRANCH="$PROD" run_bump_on "patch" "$PROD")
VERSION_LINE=$(echo "$OUTPUT" | grep "^version=" | head -1)
RC_LINE=$(echo "$OUTPUT" | grep "^rc_version=" | head -1)
assert_eq "version=2.4.1 rc_version=" "$VERSION_LINE $RC_LINE"
cleanup_test_repo "$TMPDIR"

TMPDIR=$(setup_test_repo)
cd "$TMPDIR"
setup_two_branch_hotfix
git commit -q --allow-empty -m "fix: hotfix without a version bump"
PROD=$(git branch --show-current)
HEAD_BEFORE=$(git rev-parse HEAD)

test_start "hotfix to production without a bump: skipped, never rewrites production"
OUTPUT=$(PROD_BRANCH="$PROD" run_bump_on "patch" "$PROD")
CHANGED_LINE=$(echo "$OUTPUT" | grep "^version_changed=" | head -1)
assert_eq "version_changed=false $HEAD_BEFORE" "$CHANGED_LINE $(git rev-parse HEAD)"
cleanup_test_repo "$TMPDIR"

# --- Summary ---
test_summary "bump-version integration"
