#!/bin/bash
# The updater itself must reject DSM 8; the optional runtime probe is not its gate.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/dsm_runtime_fixture.sh
source "$(dirname "$0")/../lib/dsm_runtime_fixture.sh"

# Arrange: the updater reads DSM 8 from the package's VERSION file.
prepare_dsm_runtime_fixture
set_mock_dsm_version 8 8.0
command='restore' # Restore skips version availability checks, but not DSM support.

# Act: run the updater's own version detection and compatibility check.
if update_output=$(detect_current_versions 2>&1); then
  printf 'FAIL: updater accepted unsupported DSM 8\n' >&2
  exit 1
fi

# Expect: the updater rejects this DSM version, not an unrelated missing tool.
expect_contains "$update_output" 'Current DSM version: 8.0' 'updater detects DSM 8'
expect_contains "$update_output" 'This script supports DSM 6 and 7 only' 'updater rejects DSM 8'
