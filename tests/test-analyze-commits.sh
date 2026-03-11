#!/usr/bin/env bash
set -euo pipefail

# test-analyze-commits.sh
# Tests for the commit classification logic in scripts/analyze-commits.sh.
# Extracts the grep-based detection and tests it in isolation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

# Replicate the classification logic from analyze-commits.sh
# Uses separate subjects/bodies like the real script:
# - Type prefix and ! checked on subjects only (avoids false positives from body text)
# - BREAKING CHANGE footer checked on full body
classify_commits() {
  local SUBJECTS="$1"
  local BODIES="${2:-$1}"
  if echo "$SUBJECTS" | grep -qE '(^|[[:space:]])[a-z]+(\(.*\))?!:' || echo "$BODIES" | grep -qE '^BREAKING CHANGE:'; then
    echo "major"
  elif echo "$SUBJECTS" | grep -qE '(^|[[:space:]])feat(\(.*\))?:'; then
    echo "minor"
  else
    echo "patch"
  fi
}

echo "=== analyze-commits.sh ==="

# --- MAJOR: breaking change via ! ---

test_start "major: feat!: breaking"
assert_eq "major" "$(classify_commits "feat!: drop legacy api")"

test_start "major: fix!: breaking"
assert_eq "major" "$(classify_commits "fix!: remove deprecated endpoint")"

test_start "major: chore!: breaking"
assert_eq "major" "$(classify_commits "chore!: drop node 14 support")"

test_start "major: refactor!: breaking"
assert_eq "major" "$(classify_commits "refactor!: rewrite auth module")"

test_start "major: feat(scope)!: breaking with scope"
assert_eq "major" "$(classify_commits "feat(api)!: remove v1 endpoints")"

test_start "major: fix(scope)!: breaking with scope"
assert_eq "major" "$(classify_commits "fix(auth)!: change token format")"

# --- MAJOR: breaking change via footer ---

test_start "major: BREAKING CHANGE footer"
COMMITS="$(printf 'refactor: change auth flow\n\nBREAKING CHANGE: tokens are now JWT')"
assert_eq "major" "$(classify_commits "$COMMITS")"

# --- MAJOR: mixed with lower types ---

test_start "major: feat! mixed with fix"
COMMITS="$(printf 'fix: patch something\nfeat!: drop api v1')"
assert_eq "major" "$(classify_commits "$COMMITS")"

# --- MINOR: feat ---

test_start "minor: feat: new feature"
assert_eq "minor" "$(classify_commits "feat: add user profiles")"

test_start "minor: feat(scope): with scope"
assert_eq "minor" "$(classify_commits "feat(api): add search endpoint")"

test_start "minor: feat mixed with fix"
COMMITS="$(printf 'fix: resolve crash\nfeat: add export feature')"
assert_eq "minor" "$(classify_commits "$COMMITS")"

test_start "minor: feat mixed with chore"
COMMITS="$(printf 'chore: update deps\nfeat: add notifications')"
assert_eq "minor" "$(classify_commits "$COMMITS")"

# --- PATCH: fix and other types ---

test_start "patch: fix: bug fix"
assert_eq "patch" "$(classify_commits "fix: resolve null pointer")"

test_start "patch: fix(scope): with scope"
assert_eq "patch" "$(classify_commits "fix(ui): correct alignment")"

test_start "patch: chore only"
assert_eq "patch" "$(classify_commits "chore: update deps")"

test_start "patch: docs only"
assert_eq "patch" "$(classify_commits "docs: update readme")"

test_start "patch: ci only"
assert_eq "patch" "$(classify_commits "ci: update workflow")"

test_start "patch: refactor only"
assert_eq "patch" "$(classify_commits "refactor: simplify logic")"

test_start "patch: test only"
assert_eq "patch" "$(classify_commits "test: add unit tests")"

test_start "patch: style only"
assert_eq "patch" "$(classify_commits "style: fix formatting")"

test_start "patch: build only"
assert_eq "patch" "$(classify_commits "build: update dockerfile")"

test_start "patch: mixed non-feat non-breaking"
COMMITS="$(printf 'fix: resolve bug\nchore: update deps\ndocs: add guide')"
assert_eq "patch" "$(classify_commits "$COMMITS")"

# --- Issue reference prefix (type not at start of line) ---

test_start "minor: feat with issue ref prefix"
assert_eq "minor" "$(classify_commits "web/legal-text-delta#733 feat: add new feature")"

test_start "minor: feat(scope) with issue ref prefix"
assert_eq "minor" "$(classify_commits "web/repo#42 feat(api): add endpoint")"

test_start "minor: feat with short issue ref"
assert_eq "minor" "$(classify_commits "#123 feat: add search")"

test_start "major: feat! with issue ref prefix"
assert_eq "major" "$(classify_commits "web/repo#99 feat!: drop legacy api")"

test_start "major: fix! with issue ref prefix"
assert_eq "major" "$(classify_commits "#55 fix!: change token format")"

test_start "major: refactor! with issue ref prefix"
assert_eq "major" "$(classify_commits "org/repo#10 refactor!: rewrite module")"

test_start "patch: fix with issue ref prefix"
assert_eq "patch" "$(classify_commits "web/legal-text-delta#733 fix: resolve issue")"

test_start "patch: chore with issue ref prefix"
assert_eq "patch" "$(classify_commits "#100 chore: update deps")"

# --- False positive regression: body text must not trigger type detection ---

test_start "patch: body mentioning fix!: must not trigger major"
SUBJECT="fix: detect breaking change on any commit type"
BODY="$(printf 'fix: detect breaking change on any commit type\n\nThe regex matched feat!: for breaking changes. Per the spec,\nany type with ! is breaking (e.g. fix!:, chore!:, refactor!:).')"
assert_eq "patch" "$(classify_commits "$SUBJECT" "$BODY")"

test_start "major: BREAKING CHANGE in body still detected"
SUBJECT="refactor: change auth flow"
BODY="$(printf 'refactor: change auth flow\n\nBREAKING CHANGE: tokens are now JWT')"
assert_eq "major" "$(classify_commits "$SUBJECT" "$BODY")"

test_start "minor: body mentioning feat: must not trigger minor"
SUBJECT="docs: update changelog"
BODY="$(printf 'docs: update changelog\n\nAdded entries for feat: new api and fix: bug.')"
assert_eq "patch" "$(classify_commits "$SUBJECT" "$BODY")"

test_start "patch: body mentioning BREAKING CHANGE mid-sentence must not trigger major"
SUBJECT="fix: analyze only commit subjects"
BODY="$(printf 'fix: analyze only commit subjects\n\nkeeping %%B for BREAKING CHANGE footer detection.')"
assert_eq "patch" "$(classify_commits "$SUBJECT" "$BODY")"

test_start "major: BREAKING CHANGE as proper footer still works"
SUBJECT="refactor: rewrite module"
BODY="$(printf 'refactor: rewrite module\n\nBREAKING CHANGE: old API removed')"
assert_eq "major" "$(classify_commits "$SUBJECT" "$BODY")"

# --- Summary ---
test_summary "analyze-commits"
