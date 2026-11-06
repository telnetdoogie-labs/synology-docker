#!/bin/bash
# Docker Engine 28+ requires Synology's /bin/get_key_value utility.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/dsm_runtime_fixture.sh
source "$(dirname "$0")/../lib/dsm_runtime_fixture.sh"

# Arrange: DSM 7 test image deliberately lacks the Synology-only utility.
prepare_dsm_runtime_fixture
set_mock_dsm_version 7 7.2
expect_file_absent /bin/get_key_value 'test image must model a missing DSM key-value utility'

# Act/expect: Engine 27 does not need the utility, while 28 does.
legacy_output=$(run_runtime_probe 27)
expect_not_contains "$legacy_output" 'MISSING /bin/get_key_value' 'Engine 27 does not require get_key_value'

if probe_output=$(run_runtime_probe 28 2>&1); then
  printf 'FAIL: Docker 28 passed without /bin/get_key_value\n' >&2
  exit 1
fi
expect_contains "$probe_output" 'MISSING /bin/get_key_value' 'Docker 28 requires DSM key-value utility'
