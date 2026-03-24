#!/usr/bin/env bash
set -euo pipefail

# bump-version.sh
# Bumps version in version-file (and optional helm chart).
# For staging: bumps + creates RC number.
# For production: reads version from package.json (set by staging merge), never bumps.
#   Exception: single-branch mode (no staging branch) bumps normally.
# Outputs: version, rc_version, rc_number, version_changed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/version-utils.sh"

STAGING_REF="refs/heads/$INPUT_STAGING_BRANCH"
PRODUCTION_REF="refs/heads/$INPUT_PRODUCTION_BRANCH"

# --- Helpers ---
get_bump_priority() {
  case "$1" in
    major) echo "3" ;;
    minor) echo "2" ;;
    patch) echo "1" ;;
    *)     echo "0" ;;
  esac
}

# Returns 0 (true) if version A >= version B (semver comparison)
version_gte() {
  local a_major a_minor a_patch b_major b_minor b_patch
  IFS='.' read -r a_major a_minor a_patch <<< "$1"
  IFS='.' read -r b_major b_minor b_patch <<< "$2"
  if [ "$a_major" -gt "$b_major" ]; then return 0; fi
  if [ "$a_major" -lt "$b_major" ]; then return 1; fi
  if [ "$a_minor" -gt "$b_minor" ]; then return 0; fi
  if [ "$a_minor" -lt "$b_minor" ]; then return 1; fi
  if [ "$a_patch" -ge "$b_patch" ]; then return 0; fi
  return 1
}

# ===== PRODUCTION =====
if [ "$GITHUB_REF" = "$PRODUCTION_REF" ]; then

  CURRENT_VERSION=$(read_version "$INPUT_VERSION_FILE")

  # No meaningful commits: skip entirely
  if [ "$BUMP_TYPE" = "none" ]; then
    echo "No meaningful commits to release, skipping"
    echo "version=$CURRENT_VERSION" >> "$GITHUB_OUTPUT"
    echo "rc_version=" >> "$GITHUB_OUTPUT"
    echo "rc_number=" >> "$GITHUB_OUTPUT"
    echo "version_changed=false" >> "$GITHUB_OUTPUT"
    exit 0
  fi

  # Check if a staging branch exists on remote
  STAGING_EXISTS=$(git ls-remote --exit-code origin "$INPUT_STAGING_BRANCH" >/dev/null 2>&1 && echo "true" || echo "false")

  if [ "$STAGING_EXISTS" = "true" ]; then
    # In two-branch mode, version comes from the staging merge.
    # If the tag already exists, it was already released.
    if git rev-parse "v$CURRENT_VERSION" >/dev/null 2>&1; then
      echo "Release tag v$CURRENT_VERSION already exists, skipping (already released)"
      echo "version=$CURRENT_VERSION" >> "$GITHUB_OUTPUT"
      echo "rc_version=" >> "$GITHUB_OUTPUT"
      echo "rc_number=" >> "$GITHUB_OUTPUT"
      echo "version_changed=false" >> "$GITHUB_OUTPUT"
      exit 0
    fi
    # --- Two-branch mode ---
    # The version in package.json comes from the staging merge. Never bump here.
    # Just validate that RC tags exist for this version (meaning staging completed its cycle).
    RC_TAG_COUNT=$(git tag -l "v${CURRENT_VERSION}-rc.*" 2>/dev/null | wc -l | tr -d ' ')

    if [ "$RC_TAG_COUNT" -gt 0 ]; then
      echo "Two-branch mode: version $CURRENT_VERSION has $RC_TAG_COUNT RC tag(s), ready for release"
      echo "version=$CURRENT_VERSION" >> "$GITHUB_OUTPUT"
      echo "rc_version=" >> "$GITHUB_OUTPUT"
      echo "rc_number=" >> "$GITHUB_OUTPUT"
      echo "version_changed=false" >> "$GITHUB_OUTPUT"
      exit 0
    fi

    # No RC tags: the staging auto-version may not have completed yet, or this is
    # a hotfix merged directly to production. Check if the merge came from staging.
    LAST_MERGE_MSG=$(git log --merges -1 --pretty=%s HEAD 2>/dev/null || echo "")
    IS_STAGING_MERGE="false"
    if echo "$LAST_MERGE_MSG" | grep -qi "$INPUT_STAGING_BRANCH"; then
      IS_STAGING_MERGE="true"
    fi

    if [ "$IS_STAGING_MERGE" = "true" ]; then
      echo "Skipping: merge from $INPUT_STAGING_BRANCH but no RC tags for v$CURRENT_VERSION (staging cycle incomplete)"
      echo "version=$CURRENT_VERSION" >> "$GITHUB_OUTPUT"
      echo "rc_version=" >> "$GITHUB_OUTPUT"
      echo "rc_number=" >> "$GITHUB_OUTPUT"
      echo "version_changed=false" >> "$GITHUB_OUTPUT"
      exit 0
    fi

    # Not a staging merge (hotfix branch merged directly to production).
    # Still do not bump: the hotfix branch should carry its own version,
    # or the next staging merge will bring the correct version.
    echo "Two-branch mode: non-staging merge (hotfix), using version from package.json: $CURRENT_VERSION"
    echo "version=$CURRENT_VERSION" >> "$GITHUB_OUTPUT"
    echo "rc_version=" >> "$GITHUB_OUTPUT"
    echo "rc_number=" >> "$GITHUB_OUTPUT"
    echo "version_changed=false" >> "$GITHUB_OUTPUT"
    exit 0
  fi

  # --- Single-branch mode (no staging branch) ---
  # This repo only has a production branch, so we must bump here.
  echo "Single-branch mode: no staging branch found, bumping version"

  LAST_PROD_TAG=$(git describe --tags --abbrev=0 --match "v[0-9]*.[0-9]*.[0-9]*" --exclude "*-rc.*" 2>/dev/null || echo "")
  if [ -z "$LAST_PROD_TAG" ]; then
    LAST_PROD_VERSION="0.0.0"
  else
    LAST_PROD_VERSION=$(echo "$LAST_PROD_TAG" | sed 's/^v//')
  fi

  IFS='.' read -r MAJOR MINOR PATCH <<< "$LAST_PROD_VERSION"
  case "$BUMP_TYPE" in
    major) EXPECTED_VERSION="$((MAJOR + 1)).0.0" ;;
    minor) EXPECTED_VERSION="${MAJOR}.$((MINOR + 1)).0" ;;
    patch) EXPECTED_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))" ;;
    *)     EXPECTED_VERSION="$CURRENT_VERSION" ;;
  esac

  VERSION_CHANGED="false"

  if version_gte "$CURRENT_VERSION" "$EXPECTED_VERSION"; then
    echo "Version already correct: $CURRENT_VERSION (expected >= $EXPECTED_VERSION)"
    VERSION="$CURRENT_VERSION"
  else
    echo "Version outdated ($CURRENT_VERSION), bumping to $EXPECTED_VERSION"

    # Bump version file
    write_version "$INPUT_VERSION_FILE" "$EXPECTED_VERSION"

    # Update Helm Chart appVersion if configured
    if [ -n "$INPUT_HELM_CHART" ] && [ -f "$INPUT_HELM_CHART" ]; then
      sed -i "s/^appVersion:.*/appVersion: \"$EXPECTED_VERSION\"/" "$INPUT_HELM_CHART"
    fi

    # Commit version bump
    git add -A
    git commit -m "chore: bump version to $EXPECTED_VERSION [skip ci]"
    git pull --rebase origin "$INPUT_PRODUCTION_BRANCH" || true
    git push origin "$INPUT_PRODUCTION_BRANCH"

    VERSION="$EXPECTED_VERSION"
    VERSION_CHANGED="true"
  fi

  echo "version=$VERSION" >> "$GITHUB_OUTPUT"
  echo "rc_version=" >> "$GITHUB_OUTPUT"
  echo "rc_number=" >> "$GITHUB_OUTPUT"
  echo "version_changed=$VERSION_CHANGED" >> "$GITHUB_OUTPUT"
  exit 0
fi

# ===== STAGING =====

# No meaningful commits: skip entirely
if [ "$BUMP_TYPE" = "none" ]; then
  CURRENT_VERSION=$(read_version "$INPUT_VERSION_FILE")
  echo "No meaningful commits to release, skipping"
  echo "version=$CURRENT_VERSION" >> "$GITHUB_OUTPUT"
  echo "rc_version=" >> "$GITHUB_OUTPUT"
  echo "rc_number=" >> "$GITHUB_OUTPUT"
  echo "version_changed=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

CURRENT_VERSION=$(read_version "$INPUT_VERSION_FILE")
NEEDS_REBUMP="false"
NEEDS_BUMP="false"
BASE_VERSION="$CURRENT_VERSION"

# If subsequent RC, check if we need a higher bump
if [ "$IS_SUBSEQUENT_RC" = "true" ]; then
  LAST_PROD_TAG=$(git describe --tags --abbrev=0 --match "v[0-9]*.[0-9]*.[0-9]*" --exclude "*-rc.*" 2>/dev/null || echo "")
  if [ -n "$LAST_PROD_TAG" ]; then
    LAST_PROD_VERSION=$(echo "$LAST_PROD_TAG" | sed 's/^v//')
  else
    LAST_PROD_VERSION="0.0.0"
  fi

  IFS='.' read -r LAST_MAJOR LAST_MINOR LAST_PATCH <<< "$LAST_PROD_VERSION"
  IFS='.' read -r CURR_MAJOR CURR_MINOR CURR_PATCH <<< "$CURRENT_VERSION"

  if [ "$CURR_MAJOR" -gt "$LAST_MAJOR" ]; then
    CURRENT_BUMP_TYPE="major"
  elif [ "$CURR_MINOR" -gt "$LAST_MINOR" ]; then
    CURRENT_BUMP_TYPE="minor"
  elif [ "$CURR_PATCH" -gt "$LAST_PATCH" ]; then
    CURRENT_BUMP_TYPE="patch"
  else
    CURRENT_BUMP_TYPE="unknown"
  fi

  CURRENT_PRIORITY=$(get_bump_priority "$CURRENT_BUMP_TYPE")
  NEW_PRIORITY=$(get_bump_priority "$BUMP_TYPE")

  echo "Current v$CURRENT_VERSION is a '$CURRENT_BUMP_TYPE' bump from v$LAST_PROD_VERSION"
  echo "New commits require '$BUMP_TYPE' bump"

  if [ "$NEW_PRIORITY" -gt "$CURRENT_PRIORITY" ]; then
    echo "Higher bump type detected: $CURRENT_BUMP_TYPE -> $BUMP_TYPE"
    NEEDS_REBUMP="true"
  else
    echo "Current bump type already satisfies — will create additional RC"
    BASE_VERSION="$CURRENT_VERSION"
    NEEDS_BUMP="false"
  fi
fi

# Perform version bump if needed (RC-1 or re-bump for higher priority)
if [ "$IS_SUBSEQUENT_RC" = "false" ] || [ "$NEEDS_REBUMP" = "true" ]; then
  LAST_PROD_TAG=$(git describe --tags --abbrev=0 --match "v[0-9]*.[0-9]*.[0-9]*" --exclude "*-rc.*" 2>/dev/null || echo "")
  if [ -z "$LAST_PROD_TAG" ]; then
    LAST_PROD_VERSION="0.0.0"
    echo "No previous production release found, starting from 0.0.0"
  else
    LAST_PROD_VERSION=$(echo "$LAST_PROD_TAG" | sed 's/^v//')
    echo "Last production release: v$LAST_PROD_VERSION"
  fi

  IFS='.' read -r MAJOR MINOR PATCH <<< "$LAST_PROD_VERSION"
  case "$BUMP_TYPE" in
    major) EXPECTED_VERSION="$((MAJOR + 1)).0.0" ;;
    minor) EXPECTED_VERSION="${MAJOR}.$((MINOR + 1)).0" ;;
    patch) EXPECTED_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))" ;;
    *)     echo "Invalid bump type: $BUMP_TYPE"; exit 1 ;;
  esac

  echo "Expected version (bump $BUMP_TYPE from v$LAST_PROD_VERSION): $EXPECTED_VERSION"

  if [ "$CURRENT_VERSION" != "$EXPECTED_VERSION" ]; then
    echo "Bumping version: $CURRENT_VERSION -> $EXPECTED_VERSION"

    # Bump version file
    write_version "$INPUT_VERSION_FILE" "$EXPECTED_VERSION"

    # Update Helm Chart appVersion if configured
    if [ -n "$INPUT_HELM_CHART" ] && [ -f "$INPUT_HELM_CHART" ]; then
      sed -i "s/^appVersion:.*/appVersion: \"$EXPECTED_VERSION\"/" "$INPUT_HELM_CHART"
    fi

    # Commit version bump
    git add -A
    git commit -m "chore: bump version to $EXPECTED_VERSION [skip ci]"
    git pull --rebase origin "$INPUT_STAGING_BRANCH" || true
    git push origin "$INPUT_STAGING_BRANCH"

    BASE_VERSION="$EXPECTED_VERSION"
    NEEDS_BUMP="true"
    echo "Bumped from $CURRENT_VERSION to $EXPECTED_VERSION"
  else
    echo "Version is already correct: $CURRENT_VERSION"
    NEEDS_BUMP="false"
    BASE_VERSION="$CURRENT_VERSION"
  fi
fi

# Calculate RC number
HIGHEST_RC=0
for tag in $(git tag -l "v${BASE_VERSION}-rc.*" 2>/dev/null || echo ""); do
  RC_NUM=$(echo "$tag" | sed -n 's/.*-rc\.\([0-9]*\)$/\1/p')
  if [ -n "$RC_NUM" ] && [ "$RC_NUM" -gt "$HIGHEST_RC" ]; then
    HIGHEST_RC=$RC_NUM
  fi
done

NEXT_RC=$((HIGHEST_RC + 1))
RC_VERSION="${BASE_VERSION}-rc.${NEXT_RC}"

echo "version=$BASE_VERSION" >> "$GITHUB_OUTPUT"
echo "rc_version=$RC_VERSION" >> "$GITHUB_OUTPUT"
echo "rc_number=$NEXT_RC" >> "$GITHUB_OUTPUT"
echo "version_changed=$NEEDS_BUMP" >> "$GITHUB_OUTPUT"
echo "RC version: v$RC_VERSION (base: $BASE_VERSION, RC: $NEXT_RC)"
