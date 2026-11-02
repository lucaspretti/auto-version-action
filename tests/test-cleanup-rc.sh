#!/usr/bin/env bash
set -euo pipefail

# test-cleanup-rc.sh
# Tests for RC cleanup version comparison logic in scripts/cleanup-rc.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.sh"

# Replicate the should_delete comparison from cleanup-rc.sh:38-47
should_delete_rc() {
  local RC_VER="$1"
  local CURR_VER="$2"
  local RC_MAJOR RC_MINOR RC_PATCH CURR_MAJOR CURR_MINOR CURR_PATCH
  IFS='.' read -r RC_MAJOR RC_MINOR RC_PATCH <<< "$RC_VER"
  IFS='.' read -r CURR_MAJOR CURR_MINOR CURR_PATCH <<< "$CURR_VER"

  if [ "$RC_MAJOR" -lt "$CURR_MAJOR" ]; then echo "true"; return; fi
  if [ "$RC_MAJOR" -eq "$CURR_MAJOR" ]; then
    if [ "$RC_MINOR" -lt "$CURR_MINOR" ]; then echo "true"; return; fi
    if [ "$RC_MINOR" -eq "$CURR_MINOR" ] && [ "$RC_PATCH" -le "$CURR_PATCH" ]; then echo "true"; return; fi
  fi
  echo "false"
}

# Replicate RC tag parsing from cleanup-rc.sh:34
parse_rc_version() {
  echo "$1" | sed -E 's/^v([0-9]+\.[0-9]+\.[0-9]+)-rc\.[0-9]+$/\1/'
}

echo "=== cleanup-rc.sh ==="

# --- Version comparison: should delete ---

test_start "should_delete: equal version (delete)"
assert_eq "true" "$(should_delete_rc "1.0.0" "1.0.0")"

test_start "should_delete: RC patch lower (delete)"
assert_eq "true" "$(should_delete_rc "1.0.0" "1.0.1")"

test_start "should_delete: RC minor lower (delete)"
assert_eq "true" "$(should_delete_rc "1.0.0" "1.1.0")"

test_start "should_delete: RC major lower (delete)"
assert_eq "true" "$(should_delete_rc "1.0.0" "2.0.0")"

test_start "should_delete: escalation scenario (delete)"
assert_eq "true" "$(should_delete_rc "1.0.5" "1.1.0")"

test_start "should_delete: old major (delete)"
assert_eq "true" "$(should_delete_rc "0.9.9" "1.0.0")"

# --- Version comparison: should keep ---

test_start "should_keep: RC minor higher (keep)"
assert_eq "false" "$(should_delete_rc "1.1.0" "1.0.0")"

test_start "should_keep: RC major higher (keep)"
assert_eq "false" "$(should_delete_rc "2.0.0" "1.0.0")"

test_start "should_keep: RC patch higher (keep)"
assert_eq "false" "$(should_delete_rc "1.0.2" "1.0.1")"

test_start "should_keep: higher minor RC preserved during escalation"
assert_eq "false" "$(should_delete_rc "1.1.0" "1.0.5")"

# --- RC tag parsing ---

test_start "parse_rc: v1.0.0-rc.1"
assert_eq "1.0.0" "$(parse_rc_version "v1.0.0-rc.1")"

test_start "parse_rc: v2.3.1-rc.15"
assert_eq "2.3.1" "$(parse_rc_version "v2.3.1-rc.15")"

test_start "parse_rc: v0.1.0-rc.1"
assert_eq "0.1.0" "$(parse_rc_version "v0.1.0-rc.1")"

test_start "parse_rc: v10.20.30-rc.99"
assert_eq "10.20.30" "$(parse_rc_version "v10.20.30-rc.99")"

# --- Summary ---
test_summary "cleanup-rc"
