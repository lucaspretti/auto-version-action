#!/usr/bin/env bash
set -euo pipefail

# analyze-commits.sh
# Analyzes conventional commits since last production tag to determine bump type.
# Outputs: type (major|minor|patch), is_subsequent_rc (true|false), current_version

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/version-utils.sh"

# Read current version from version file
CURRENT_VERSION=$(read_version "$INPUT_VERSION_FILE")
echo "current_version=$CURRENT_VERSION" >> "$GITHUB_OUTPUT"
echo "Current version: $CURRENT_VERSION"

STAGING_REF="refs/heads/$INPUT_STAGING_BRANCH"

# For staging: Check if RC tags exist for current version
if [ "$GITHUB_REF" = "$STAGING_REF" ]; then
  EXISTING_RC_COUNT=$(git tag -l "v${CURRENT_VERSION}-rc.*" 2>/dev/null | wc -l | tr -d ' ')
  LAST_PROD_TAG=$(last_release_tag)

  if [ "$EXISTING_RC_COUNT" -gt 0 ]; then
    echo "RC tags already exist for v$CURRENT_VERSION (found $EXISTING_RC_COUNT RC(s))"
    echo "Checking if new commits require a higher version bump..."
    echo "is_subsequent_rc=true" >> "$GITHUB_OUTPUT"
  else
    echo "No RC tags exist for v$CURRENT_VERSION — this will be RC-1"
    echo "is_subsequent_rc=false" >> "$GITHUB_OUTPUT"
  fi
else
  LAST_PROD_TAG=$(last_release_tag)
  echo "is_subsequent_rc=false" >> "$GITHUB_OUTPUT"
fi

# Get commits since last production release
# Use %s (subject only) for type/! detection, %B (full body) for BREAKING CHANGE footer
if [ -z "$LAST_PROD_TAG" ]; then
  ROOT_COMMIT=$(git rev-list --max-parents=0 HEAD | head -1)
  ALL_SUBJECTS=$(git log --pretty=%s --no-merges "$ROOT_COMMIT..HEAD")
  ALL_BODIES=$(git log --pretty=%B --no-merges "$ROOT_COMMIT..HEAD")
  RANGE_DESC="all commits (no previous tag found)"
else
  ALL_SUBJECTS=$(git log --pretty=%s --no-merges "$LAST_PROD_TAG..HEAD")
  ALL_BODIES=$(git log --pretty=%B --no-merges "$LAST_PROD_TAG..HEAD")
  RANGE_DESC="since $LAST_PROD_TAG"
fi

echo "Analyzing commits $RANGE_DESC"

# Filter out [skip ci] / [ci skip] commits (automated bumps, syncs)
SUBJECTS=$(echo "$ALL_SUBJECTS" | grep -v '\[skip ci\]\|\[ci skip\]' || true)
BODIES=$(echo "$ALL_BODIES" | grep -v '\[skip ci\]\|\[ci skip\]' || true)

if [ -z "$SUBJECTS" ]; then
  echo "No meaningful commits found (all are [skip ci]) -- skipping"
  echo "type=none" >> "$GITHUB_OUTPUT"
else
  # Determine bump type from conventional commits
  # Type prefix and ! are checked on subject lines only to avoid false positives from body text
  # BREAKING CHANGE footer must start at beginning of line followed by colon (per conventional commits spec)
  if echo "$SUBJECTS" | grep -qE '(^|[[:space:]])[a-z]+(\(.*\))?!:' || echo "$BODIES" | grep -qE '^BREAKING CHANGE:'; then
    echo "Found breaking change -- MAJOR version bump"
    echo "type=major" >> "$GITHUB_OUTPUT"
  elif echo "$SUBJECTS" | grep -qE '(^|[[:space:]])feat(\(.*\))?:'; then
    echo "Found feature -- MINOR version bump"
    echo "type=minor" >> "$GITHUB_OUTPUT"
  else
    echo "Only fixes/chores -- PATCH version bump"
    echo "type=patch" >> "$GITHUB_OUTPUT"
  fi
fi
