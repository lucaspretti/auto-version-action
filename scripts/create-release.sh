#!/usr/bin/env bash
set -euo pipefail

# create-release.sh
# Creates RC pre-release (staging) or production release with categorized changelog.

STAGING_REF="refs/heads/$INPUT_STAGING_BRANCH"
PRODUCTION_REF="refs/heads/$INPUT_PRODUCTION_BRANCH"
REPO_URL="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY"
API_URL="$INPUT_GITHUB_API_URL/repos/$GITHUB_REPOSITORY"

# --- Shared: categorize commits ---
categorize_commits() {
  local range="$1"
  local fmt="- %s ([%h]($REPO_URL/commit/%H))"

  CHANGELOG=$(git log --pretty=format:"$fmt" $range)
  TOTAL_COMMITS=$(git rev-list --count $range)
  BREAKING=$(echo "$CHANGELOG" | grep -E "^- feat(\(.*\))?!:|BREAKING CHANGE" || echo "")
  FEATURES=$(echo "$CHANGELOG" | grep -E "^- feat(\(.*\))?:" | grep -v "!" || echo "")
  FIXES=$(echo "$CHANGELOG" | grep -E "^- fix(\(.*\))?:" || echo "")
  CHORES=$(echo "$CHANGELOG" | grep -E "^- (chore|docs|style|refactor|perf|test)(\(.*\))?:" || echo "")
  OTHER=$(echo "$CHANGELOG" | grep -vE "^- (feat|fix|chore|docs|style|refactor|perf|test)(\(.*\))?:" || echo "")
}

# --- Shared: write categorized sections to release_notes.md ---
write_sections() {
  local has_sections="false"

  if [ -n "$BREAKING" ]; then
    printf '### Breaking Changes\n\n%s\n\n' "$BREAKING" >> release_notes.md
    has_sections="true"
  fi
  if [ -n "$FEATURES" ]; then
    printf '### New Features\n\n%s\n\n' "$FEATURES" >> release_notes.md
    has_sections="true"
  fi
  if [ -n "$FIXES" ]; then
    printf '### Bug Fixes\n\n%s\n\n' "$FIXES" >> release_notes.md
    has_sections="true"
  fi
  if [ -n "$CHORES" ]; then
    printf '### Maintenance & Improvements\n\n%s\n\n' "$CHORES" >> release_notes.md
    has_sections="true"
  fi
  if [ -n "$OTHER" ]; then
    printf '### Other Changes\n\n%s\n\n' "$OTHER" >> release_notes.md
    has_sections="true"
  fi

  if [ "$has_sections" = "false" ]; then
    printf '### Changes\n\n%s\n\n' "$CHANGELOG" >> release_notes.md
  fi
}

# ==========================================================
# STAGING: Create RC tag + Pre-release
# ==========================================================
if [ "$GITHUB_REF" = "$STAGING_REF" ]; then
  echo "Creating RC release: v$RC_VERSION"

  # Determine commit range
  if [ "$RC_NUMBER" = "1" ]; then
    LAST_TAG=$(git describe --tags --abbrev=0 --exclude "*-rc.*" 2>/dev/null || echo "")
  else
    PREV_RC=$((RC_NUMBER - 1))
    LAST_TAG="v${BASE_VERSION}-rc.${PREV_RC}"
  fi

  if [ -z "$LAST_TAG" ]; then
    RANGE="HEAD~10..HEAD"
    RANGE_DESC="last 10 commits"
    FULL_CHANGELOG_URL="$REPO_URL/commits/$INPUT_STAGING_BRANCH"
    FULL_CHANGELOG_LABEL="**Commit History**"
  else
    RANGE="$LAST_TAG..HEAD"
    RANGE_DESC="$LAST_TAG -> v$RC_VERSION"
    FULL_CHANGELOG_URL="$REPO_URL/compare/$LAST_TAG...v$RC_VERSION"
    FULL_CHANGELOG_LABEL="**Full Changelog**"
  fi

  categorize_commits "$RANGE"

  # Build release notes
  printf '## Staging Release Candidate v%s\n\n' "$RC_VERSION" > release_notes.md
  printf '**This is RC #%s for version %s (staging only).**\n\n' "$RC_NUMBER" "$BASE_VERSION" >> release_notes.md
  printf '**Version Type**: `%s` bump\n' "$BUMP_TYPE" >> release_notes.md
  printf '**Commits**: %s changes (%s)\n' "$TOTAL_COMMITS" "$RANGE_DESC" >> release_notes.md
  printf '**Created**: %s\n\n' "$(date -u +'%Y-%m-%d %H:%M UTC')" >> release_notes.md

  write_sections

  printf '%s\n\n### Deployment\n\n' '---' >> release_notes.md
  if [ -n "$INPUT_DEPLOYMENT_INFO" ]; then
    printf '%s\n' "$INPUT_DEPLOYMENT_INFO" >> release_notes.md
  else
    printf '- **Status**: Release Candidate %s\n' "$RC_NUMBER" >> release_notes.md
    printf '- **Not for production use**\n' >> release_notes.md
  fi
  printf '\n%s: %s\n' "$FULL_CHANGELOG_LABEL" "$FULL_CHANGELOG_URL" >> release_notes.md

  # Create RC tag (immutable)
  git tag -a "v$RC_VERSION" -m "Release Candidate v$RC_VERSION"
  git push origin "v$RC_VERSION"

  # Create GitHub pre-release
  RELEASE_NOTES=$(cat release_notes.md)
  curl -L -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$API_URL/releases" \
    -d "{
      \"tag_name\": \"v$RC_VERSION\",
      \"target_commitish\": \"$INPUT_STAGING_BRANCH\",
      \"name\": \"v$RC_VERSION (Release Candidate)\",
      \"body\": $(echo "$RELEASE_NOTES" | jq -Rs .),
      \"draft\": false,
      \"prerelease\": true
    }"

  echo "Release Candidate v$RC_VERSION created successfully"
  exit 0
fi

# ==========================================================
# PRODUCTION: Create tag + Release
# ==========================================================
if [ "$GITHUB_REF" = "$PRODUCTION_REF" ]; then
  VERSION="$BASE_VERSION"
  echo "Creating production release: v$VERSION"

  # Delete existing tag/release if present (re-run scenario)
  if git rev-parse "v$VERSION" >/dev/null 2>&1; then
    echo "Tag v$VERSION already exists, deleting to recreate"
    RELEASE_ID=$(curl -s -L \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$API_URL/releases/tags/v$VERSION" \
      | jq -r '.id // empty')

    if [ -n "$RELEASE_ID" ]; then
      curl -L -X DELETE \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$API_URL/releases/$RELEASE_ID"
    fi
    git push origin --delete "v$VERSION" || true
    git tag -d "v$VERSION" || true
  fi

  # Create production tag
  git tag -a "v$VERSION" -m "v$VERSION"
  git push origin "v$VERSION"

  # Find last production tag (exclude RCs and current)
  LAST_PROD_TAG=$(git describe --tags --abbrev=0 --exclude "*-rc.*" --exclude "v${VERSION}" HEAD^ 2>/dev/null || echo "")

  if [ -z "$LAST_PROD_TAG" ]; then
    RANGE="HEAD~10..HEAD"
    RANGE_DESC="last 10 commits"
  else
    RANGE="$LAST_PROD_TAG..HEAD"
    RANGE_DESC="$LAST_PROD_TAG -> v$VERSION"
  fi

  categorize_commits "$RANGE"

  BUILD_TIME=$(date -u +'%Y-%m-%d %H:%M:%S UTC')
  COMMIT_SHA_SHORT="${GITHUB_SHA:0:7}"

  # Build release notes
  printf '## What'\''s New in v%s\n\n' "$VERSION" > release_notes.md
  printf '**Version Type**: `%s` bump\n' "$BUMP_TYPE" >> release_notes.md
  printf '**Commits**: %s changes (%s)\n\n' "$TOTAL_COMMITS" "$RANGE_DESC" >> release_notes.md

  write_sections

  printf '%s\n\n' '---' >> release_notes.md

  if [ -n "$INPUT_DEPLOYMENT_INFO" ]; then
    printf '## Deployment Information\n\n%s\n\n' "$INPUT_DEPLOYMENT_INFO" >> release_notes.md
  fi

  printf '### Build Details\n\n' >> release_notes.md
  printf '- **Docker Image**: `%s` ([view commit](%s/commit/%s))\n' "$COMMIT_SHA_SHORT" "$REPO_URL" "$GITHUB_SHA" >> release_notes.md
  printf '- **Workflow Run**: [View logs](%s/actions/runs/%s)\n' "$REPO_URL" "$GITHUB_RUN_ID" >> release_notes.md
  printf '- **Build Time**: %s\n' "$BUILD_TIME" >> release_notes.md
  printf '- **Deployed By**: @%s\n\n' "$GITHUB_ACTOR" >> release_notes.md
  printf '%s\n\n' '---' >> release_notes.md

  if [ -n "$LAST_PROD_TAG" ]; then
    printf '**Full Changelog**: %s/compare/%s...v%s\n' "$REPO_URL" "$LAST_PROD_TAG" "$VERSION" >> release_notes.md
  fi

  # Create GitHub release
  RELEASE_NOTES=$(cat release_notes.md)
  RELEASE_RESPONSE=$(curl -s -w "\n%{http_code}" -L -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$API_URL/releases" \
    -d "{
      \"tag_name\": \"v$VERSION\",
      \"target_commitish\": \"$GITHUB_REF_NAME\",
      \"name\": \"v$VERSION\",
      \"body\": $(echo "$RELEASE_NOTES" | jq -Rs .),
      \"draft\": false,
      \"prerelease\": false,
      \"make_latest\": \"true\"
    }")

  HTTP_CODE=$(echo "$RELEASE_RESPONSE" | tail -n1)
  RELEASE_BODY=$(echo "$RELEASE_RESPONSE" | sed '$d')

  if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
    RELEASE_URL=$(echo "$RELEASE_BODY" | jq -r '.html_url // empty')
    echo "Release created successfully: $RELEASE_URL"
  else
    echo "::error::Failed to create release (HTTP $HTTP_CODE)"
    echo "Response: $RELEASE_BODY"
    exit 1
  fi
fi
