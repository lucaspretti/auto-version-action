#!/usr/bin/env bash
set -euo pipefail

# test-create-release.sh
# Tests for changelog categorization and section writing in scripts/create-release.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Replicate the grep categorization from create-release.sh:13-24
categorize_line() {
  local line="$1"
  if echo "$line" | grep -qE "^- [a-z]+(\(.*\))?!:|BREAKING CHANGE"; then echo "breaking"
  elif echo "$line" | grep -qE "^- feat(\(.*\))?:" && ! echo "$line" | grep -q "!"; then echo "feature"
  elif echo "$line" | grep -qE "^- fix(\(.*\))?:"; then echo "fix"
  elif echo "$line" | grep -qE "^- (chore|docs|style|refactor|perf|test)(\(.*\))?:"; then echo "maintenance"
  else echo "other"
  fi
}

# Replicate write_sections from create-release.sh:27-54
write_sections() {
  local outfile="$1"
  > "$outfile"
  local has_sections="false"

  if [ -n "$BREAKING" ]; then
    printf '### Breaking Changes\n\n%s\n\n' "$BREAKING" >> "$outfile"
    has_sections="true"
  fi
  if [ -n "$FEATURES" ]; then
    printf '### New Features\n\n%s\n\n' "$FEATURES" >> "$outfile"
    has_sections="true"
  fi
  if [ -n "$FIXES" ]; then
    printf '### Bug Fixes\n\n%s\n\n' "$FIXES" >> "$outfile"
    has_sections="true"
  fi
  if [ -n "$CHORES" ]; then
    printf '### Maintenance & Improvements\n\n%s\n\n' "$CHORES" >> "$outfile"
    has_sections="true"
  fi
  if [ -n "$OTHER" ]; then
    printf '### Other Changes\n\n%s\n\n' "$OTHER" >> "$outfile"
    has_sections="true"
  fi

  if [ "$has_sections" = "false" ]; then
    printf '### Changes\n\n%s\n\n' "$CHANGELOG" >> "$outfile"
  fi
}

echo "=== create-release.sh ==="

# --- Categorization ---

test_start "categorize: feat: as feature"
assert_eq "feature" "$(categorize_line "- feat: add new feature (abc1234)")"

test_start "categorize: feat(scope): as feature"
assert_eq "feature" "$(categorize_line "- feat(api): add search endpoint (abc1234)")"

test_start "categorize: feat!: as breaking"
assert_eq "breaking" "$(categorize_line "- feat!: redesign API (abc1234)")"

test_start "categorize: feat(scope)!: as breaking"
assert_eq "breaking" "$(categorize_line "- feat(api)!: remove v1 endpoints (abc1234)")"

test_start "categorize: BREAKING CHANGE in line as breaking"
assert_eq "breaking" "$(categorize_line "- refactor: change auth BREAKING CHANGE (abc1234)")"

test_start "categorize: fix!: as breaking"
assert_eq "breaking" "$(categorize_line "- fix!: change token format (abc1234)")"

test_start "categorize: chore!: as breaking"
assert_eq "breaking" "$(categorize_line "- chore!: drop node 14 support (abc1234)")"

test_start "categorize: refactor(scope)!: as breaking"
assert_eq "breaking" "$(categorize_line "- refactor(auth)!: rewrite module (abc1234)")"

test_start "categorize: fix: as fix"
assert_eq "fix" "$(categorize_line "- fix: resolve null pointer (abc1234)")"

test_start "categorize: fix(scope): as fix"
assert_eq "fix" "$(categorize_line "- fix(ui): correct alignment (abc1234)")"

test_start "categorize: chore: as maintenance"
assert_eq "maintenance" "$(categorize_line "- chore: update deps (abc1234)")"

test_start "categorize: docs: as maintenance"
assert_eq "maintenance" "$(categorize_line "- docs: update readme (abc1234)")"

test_start "categorize: refactor: as maintenance"
assert_eq "maintenance" "$(categorize_line "- refactor: simplify logic (abc1234)")"

test_start "categorize: perf: as maintenance"
assert_eq "maintenance" "$(categorize_line "- perf: optimize query (abc1234)")"

test_start "categorize: test: as maintenance"
assert_eq "maintenance" "$(categorize_line "- test: add unit tests (abc1234)")"

test_start "categorize: style: as maintenance"
assert_eq "maintenance" "$(categorize_line "- style: fix formatting (abc1234)")"

test_start "categorize: build: as other"
assert_eq "other" "$(categorize_line "- build: update dockerfile (abc1234)")"

test_start "categorize: ci: as other"
assert_eq "other" "$(categorize_line "- ci: update workflow (abc1234)")"

test_start "categorize: random message as other"
assert_eq "other" "$(categorize_line "- update something (abc1234)")"

# --- Skip CI filtering ---

test_start "skip-ci: filters out [skip ci] commits"
CHANGELOG="$(printf -- '- feat: real feature (abc1234)\n- chore: bump version [skip ci] (def5678)\n- fix: real fix (ghi9012)')"
FILTERED=$(echo "$CHANGELOG" | grep -v "\[skip ci\]" || echo "")
FILTERED_COUNT=$(echo "$FILTERED" | wc -l | tr -d ' ')
assert_eq "2" "$FILTERED_COUNT"

test_start "skip-ci: keeps non-skip-ci commits intact"
FIRST_LINE=$(echo "$FILTERED" | head -1)
assert_eq "- feat: real feature (abc1234)" "$FIRST_LINE"

# --- write_sections ---

test_start "write_sections: all categories present"
BREAKING="- feat!: drop api (abc)"
FEATURES="- feat: add search (def)"
FIXES="- fix: null pointer (ghi)"
CHORES="- chore: update deps (jkl)"
OTHER="- ci: update workflow (mno)"
CHANGELOG=""
write_sections "$TMPDIR_TEST/sections.md"
CONTENT=$(cat "$TMPDIR_TEST/sections.md")
if echo "$CONTENT" | grep -q "### Breaking Changes" && \
   echo "$CONTENT" | grep -q "### New Features" && \
   echo "$CONTENT" | grep -q "### Bug Fixes" && \
   echo "$CONTENT" | grep -q "### Maintenance & Improvements" && \
   echo "$CONTENT" | grep -q "### Other Changes"; then
  assert_true "all 5 sections present"
else
  assert_unexpected "missing sections"
fi

test_start "write_sections: only fixes"
BREAKING="" FEATURES="" FIXES="- fix: bug (abc)" CHORES="" OTHER=""
write_sections "$TMPDIR_TEST/fixes-only.md"
CONTENT=$(cat "$TMPDIR_TEST/fixes-only.md")
if echo "$CONTENT" | grep -q "### Bug Fixes" && \
   ! echo "$CONTENT" | grep -q "### New Features" && \
   ! echo "$CONTENT" | grep -q "### Breaking Changes"; then
  assert_true "only Bug Fixes section"
else
  assert_unexpected "unexpected sections"
fi

test_start "write_sections: empty categories fallback to Changes"
BREAKING="" FEATURES="" FIXES="" CHORES="" OTHER=""
CHANGELOG="- some commit (abc)"
write_sections "$TMPDIR_TEST/fallback.md"
CONTENT=$(cat "$TMPDIR_TEST/fallback.md")
if echo "$CONTENT" | grep -q "### Changes"; then
  assert_true "falls back to generic Changes section"
else
  assert_unexpected "missing fallback section"
fi

# --- Summary ---
test_summary "create-release"
