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
  LAST_PROD_TAG=$(git describe --tags --abbrev=0 --match "v[0-9]*.[0-9]*.[0-9]*" --exclude "*-rc.*" 2>/dev/null || echo "")

  if [ "$EXISTING_RC_COUNT" -gt 0 ]; then
    echo "RC tags already exist for v$CURRENT_VERSION (found $EXISTING_RC_COUNT RC(s))"
    echo "Checking if new commits require a higher version bump..."
    echo "is_subsequent_rc=true" >> "$GITHUB_OUTPUT"
  else
    echo "No RC tags exist for v$CURRENT_VERSION — this will be RC-1"
    echo "is_subsequent_rc=false" >> "$GITHUB_OUTPUT"
  fi
else
  LAST_PROD_TAG=$(git describe --tags --abbrev=0 --match "v[0-9]*.[0-9]*.[0-9]*" --exclude "*-rc.*" 2>/dev/null || echo "")
  echo "is_subsequent_rc=false" >> "$GITHUB_OUTPUT"
fi

# Get commits since last production release
# Use %s (subject only) for type/! detection, %B (full body) for BREAKING CHANGE footer
if [ -z "$LAST_PROD_TAG" ]; then
  SUBJECTS=$(git log --pretty=%s --no-merges HEAD~10..HEAD)
  BODIES=$(git log --pretty=%B --no-merges HEAD~10..HEAD)
  RANGE_DESC="last 10 commits (no previous tag found)"
else
  SUBJECTS=$(git log --pretty=%s --no-merges "$LAST_PROD_TAG..HEAD")
  BODIES=$(git log --pretty=%B --no-merges "$LAST_PROD_TAG..HEAD")
  RANGE_DESC="since $LAST_PROD_TAG"
fi

echo "Analyzing commits $RANGE_DESC"

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
