#!/usr/bin/env bash
set -euo pipefail

# bump-version.sh
# Bumps version in version-file (and optional helm chart).
# For staging: bumps + creates RC number.
# For production: bumps only if version is outdated (direct push without staging).
# Outputs: version, rc_version, rc_number, version_changed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/version-utils.sh"

STAGING_REF="refs/heads/$INPUT_STAGING_BRANCH"
PRODUCTION_REF="refs/heads/$INPUT_PRODUCTION_BRANCH"

# --- Helper ---
get_bump_priority() {
  case "$1" in
    major) echo "3" ;;
    minor) echo "2" ;;
    patch) echo "1" ;;
    *)     echo "0" ;;
  esac
}

# ===== PRODUCTION =====
if [ "$GITHUB_REF" = "$PRODUCTION_REF" ]; then
  CURRENT_VERSION=$(read_version "$INPUT_VERSION_FILE")

  # Calculate expected version from commits
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

  if [ "$CURRENT_VERSION" = "$EXPECTED_VERSION" ]; then
    echo "Production version already correct (from staging): $CURRENT_VERSION"
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
