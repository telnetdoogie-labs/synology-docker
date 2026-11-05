#!/bin/bash
# DSM 6 uses synoservicectl instead of the DSM 7 package command.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/dsm_runtime_fixture.sh
source "$(dirname "$0")/../lib/dsm_runtime_fixture.sh"

# Arrange: a supported DSM 6 installation with its service controller.
prepare_dsm_runtime_fixture
set_mock_dsm_version 6 6.2

# Act: probe compatibility for Docker Engine 27.
probe_output=$(run_runtime_probe 27)

# Expect: DSM 6 uses its own service tool.
expect_contains "$probe_output" 'DSM major version: 6' 'recognizes DSM 6'
expect_contains "$probe_output" 'OK      DSM 6 synoservicectl found' 'DSM 6 service tool found'
