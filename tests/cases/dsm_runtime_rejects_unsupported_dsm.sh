#!/bin/bash
# DSM major versions outside 6 and 7 must not pass the runtime probe.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/dsm_runtime_fixture.sh
source "$(dirname "$0")/../lib/dsm_runtime_fixture.sh"

# Arrange: a complete mocked runtime on an unsupported DSM 8 package.
prepare_dsm_runtime_fixture
set_mock_dsm_version 8 8.0

# Act: probe compatibility for Docker Engine 27.
if probe_output=$(run_runtime_probe 27 2>&1); then
  printf 'FAIL: unsupported DSM 8 passed the runtime probe\n' >&2
  exit 1
fi

# Expect: the failure identifies the unsupported DSM major.
expect_contains "$probe_output" 'UNSUPPORTED DSM major version: 8' 'DSM 8 reports unsupported'
