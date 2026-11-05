#!/bin/bash
# The target Docker major version must be numeric.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/dsm_runtime_fixture.sh
source "$(dirname "$0")/../lib/dsm_runtime_fixture.sh"

# Arrange: a valid DSM 7 environment, so only the target version is invalid.
prepare_dsm_runtime_fixture
set_mock_dsm_version 7 7.2

# Act: probe compatibility using a non-numeric target major.
if probe_output=$(run_runtime_probe invalid 2>&1); then
  printf 'FAIL: non-numeric Docker major passed the runtime probe\n' >&2
  exit 1
fi

# Expect: the failure explains the version contract.
expect_contains "$probe_output" 'Target Docker major version must be numeric' 'invalid Docker major explains error'
