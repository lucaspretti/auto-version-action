#!/usr/bin/env bash
set -euo pipefail

# run-all.sh
# Runs all test files in the tests/ directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERALL_EXIT=0

for test_file in "$SCRIPT_DIR"/test-*.sh; do
  echo ""
  echo "--- $(basename "$test_file") ---"
  if bash "$test_file"; then
    :
  else
    OVERALL_EXIT=1
  fi
done

echo ""
if [ "$OVERALL_EXIT" -eq 0 ]; then
  echo "All test suites passed."
else
  echo "Some test suites FAILED."
fi

exit "$OVERALL_EXIT"
