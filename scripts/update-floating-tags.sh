#!/usr/bin/env bash
set -euo pipefail

# update-floating-tags.sh
# Moves vMAJOR and vMAJOR.MINOR floating tags to point to the current release.
# Production only — skipped for RC pre-releases.

TAG="v${VERSION}"
IFS='.' read -r MAJOR MINOR _PATCH <<< "$VERSION"

MAJOR_TAG="v${MAJOR}"
MINOR_TAG="v${MAJOR}.${MINOR}"

echo "Updating floating tags: $MAJOR_TAG and $MINOR_TAG -> $TAG"

git fetch --tags --force

git tag -fa "$MAJOR_TAG" "$TAG^{}" -m "Update $MAJOR_TAG -> $TAG"
git push origin "refs/tags/$MAJOR_TAG" --force

git tag -fa "$MINOR_TAG" "$TAG^{}" -m "Update $MINOR_TAG -> $TAG"
git push origin "refs/tags/$MINOR_TAG" --force

echo "Floating tags updated successfully"
