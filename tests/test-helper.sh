#!/usr/bin/env bash
# test-helper.sh
# Minimal bash test assertion helper. Source this in test files.

_TESTS_RUN=0
_TESTS_PASSED=0
_TESTS_FAILED=0
_CURRENT_TEST=""

# Start a named test
test_start() {
  _CURRENT_TEST="$1"
  _TESTS_RUN=$((_TESTS_RUN + 1))
}

# Assert equality
assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-}"
  if [ "$expected" = "$actual" ]; then
    _TESTS_PASSED=$((_TESTS_PASSED + 1))
    printf "  PASS: %s" "$_CURRENT_TEST"
    [ -n "$msg" ] && printf " (%s)" "$msg"
    printf "\n"
  else
    _TESTS_FAILED=$((_TESTS_FAILED + 1))
    printf "  FAIL: %s" "$_CURRENT_TEST"
    [ -n "$msg" ] && printf " (%s)" "$msg"
    printf "\n    expected: '%s'\n    actual:   '%s'\n" "$expected" "$actual"
  fi
}

# Assert command exits 0 (true)
assert_true() {
  local msg="${1:-}"
  _TESTS_PASSED=$((_TESTS_PASSED + 1))
  printf "  PASS: %s" "$_CURRENT_TEST"
  [ -n "$msg" ] && printf " (%s)" "$msg"
  printf "\n"
}

# Assert command exits non-zero (false)
assert_false() {
  local msg="${1:-}"
  _TESTS_PASSED=$((_TESTS_PASSED + 1))
  printf "  PASS: %s" "$_CURRENT_TEST"
  [ -n "$msg" ] && printf " (%s)" "$msg"
  printf "\n"
}

# Called when assert_true/assert_false expectation is wrong
assert_unexpected() {
  local msg="${1:-}"
  _TESTS_FAILED=$((_TESTS_FAILED + 1))
  printf "  FAIL: %s" "$_CURRENT_TEST"
  [ -n "$msg" ] && printf " (%s)" "$msg"
  printf "\n"
}

# Print summary and exit with appropriate code
test_summary() {
  local suite="${1:-Tests}"
  printf "\n%s: %d run, %d passed, %d failed\n" "$suite" "$_TESTS_RUN" "$_TESTS_PASSED" "$_TESTS_FAILED"
  [ "$_TESTS_FAILED" -eq 0 ] && return 0 || return 1
}
