#!/usr/bin/env bash
set -euo pipefail

# summary.sh
# Writes GitHub Actions step summary.

BRANCH="$GITHUB_REF_NAME"
REPO_URL="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY"

# Get analyzed commits for summary
LAST_TAG=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo "")

if [ -z "$LAST_TAG" ]; then
  COMMITS=$(git log --pretty=format:"- %s (%h)" HEAD~10..HEAD)
  RANGE="last 10 commits"
else
  COMMITS=$(git log --pretty=format:"- %s (%h)" "$LAST_TAG..HEAD")
  RANGE="since $LAST_TAG"
fi

echo "## Version Management Summary" >> "$GITHUB_STEP_SUMMARY"
echo "" >> "$GITHUB_STEP_SUMMARY"
echo "- **Branch**: $BRANCH" >> "$GITHUB_STEP_SUMMARY"

if [ "$BRANCH" = "$INPUT_STAGING_BRANCH" ]; then
  if [ "$RC_NUMBER" = "1" ]; then
    echo "- **Action**: Version bumped + First RC created" >> "$GITHUB_STEP_SUMMARY"
    echo "- **Previous Version**: $OLD_VERSION" >> "$GITHUB_STEP_SUMMARY"
    echo "- **New Base Version**: $BASE_VERSION" >> "$GITHUB_STEP_SUMMARY"
  else
    echo "- **Action**: Additional RC created (no version bump)" >> "$GITHUB_STEP_SUMMARY"
    echo "- **Base Version**: $BASE_VERSION (unchanged)" >> "$GITHUB_STEP_SUMMARY"
  fi
  echo "- **RC Version**: $RC_VERSION" >> "$GITHUB_STEP_SUMMARY"
  echo "- **RC Number**: #$RC_NUMBER" >> "$GITHUB_STEP_SUMMARY"
else
  echo "- **Previous Version**: $OLD_VERSION" >> "$GITHUB_STEP_SUMMARY"
  echo "- **New Version**: $BASE_VERSION" >> "$GITHUB_STEP_SUMMARY"
fi

echo "- **Bump Type**: $BUMP_TYPE" >> "$GITHUB_STEP_SUMMARY"
echo "- **Docker Image Tag**: ${GITHUB_SHA:0:7}" >> "$GITHUB_STEP_SUMMARY"
echo "" >> "$GITHUB_STEP_SUMMARY"
echo "### Commits Analyzed ($RANGE)" >> "$GITHUB_STEP_SUMMARY"
echo '```' >> "$GITHUB_STEP_SUMMARY"
echo "$COMMITS" >> "$GITHUB_STEP_SUMMARY"
echo '```' >> "$GITHUB_STEP_SUMMARY"

if [ "$BRANCH" = "$INPUT_STAGING_BRANCH" ]; then
  echo "" >> "$GITHUB_STEP_SUMMARY"
  echo "**Staging RC Release**: [v$RC_VERSION]($REPO_URL/releases/tag/v$RC_VERSION)" >> "$GITHUB_STEP_SUMMARY"
else
  echo "" >> "$GITHUB_STEP_SUMMARY"
  echo "**GitHub Release created**: [v$BASE_VERSION]($REPO_URL/releases/tag/v$BASE_VERSION)" >> "$GITHUB_STEP_SUMMARY"
fi
