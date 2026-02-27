#!/usr/bin/env bash
set -euo pipefail

# cleanup-rc.sh
# Deletes all RC pre-releases with versions <= current production version.
# Handles orphaned RCs from version escalation (e.g., v1.0.5-rc.* when releasing v1.1.0).

API_URL="$INPUT_GITHUB_API_URL/repos/$GITHUB_REPOSITORY"

echo "Cleaning up RC pre-releases..."

# Get all RC pre-releases
RC_RELEASES=$(curl -s -L \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "$API_URL/releases?per_page=100" \
  | jq -r '.[] | select(.prerelease == true) | select(.tag_name != null) | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+-rc\\.")) | {id, tag_name} | @base64')

if [ -z "$RC_RELEASES" ]; then
  echo "  No RC pre-releases found"
  exit 0
fi

echo "Found RC pre-releases to evaluate..."
IFS='.' read -r CURR_MAJOR CURR_MINOR CURR_PATCH <<< "$VERSION"

for RC_DATA in $RC_RELEASES; do
  RC_JSON=$(echo "$RC_DATA" | base64 -d)
  RC_ID=$(echo "$RC_JSON" | jq -r '.id')
  RC_TAG=$(echo "$RC_JSON" | jq -r '.tag_name')

  # Extract base version from RC tag (e.g., v1.0.5-rc.1 -> 1.0.5)
  RC_VER=$(echo "$RC_TAG" | sed -E 's/^v([0-9]+\.[0-9]+\.[0-9]+)-rc\.[0-9]+$/\1/')
  IFS='.' read -r RC_MAJOR RC_MINOR RC_PATCH <<< "$RC_VER"

  # Delete if version <= current production version
  SHOULD_DELETE="false"
  if [ "$RC_MAJOR" -lt "$CURR_MAJOR" ]; then
    SHOULD_DELETE="true"
  elif [ "$RC_MAJOR" -eq "$CURR_MAJOR" ]; then
    if [ "$RC_MINOR" -lt "$CURR_MINOR" ]; then
      SHOULD_DELETE="true"
    elif [ "$RC_MINOR" -eq "$CURR_MINOR" ] && [ "$RC_PATCH" -le "$CURR_PATCH" ]; then
      SHOULD_DELETE="true"
    fi
  fi

  if [ "$SHOULD_DELETE" = "true" ]; then
    echo "  Deleting $RC_TAG (version $RC_VER <= $VERSION)"
    curl -L -X DELETE \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$API_URL/releases/$RC_ID"
  else
    echo "  Keeping $RC_TAG (version $RC_VER > $VERSION)"
  fi
done
