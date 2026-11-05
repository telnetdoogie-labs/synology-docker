#!/bin/bash
# DSM 7 passes when its package tool and required shell utilities exist.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/dsm_runtime_fixture.sh
source "$(dirname "$0")/../lib/dsm_runtime_fixture.sh"

# Arrange: model a supported DSM 7 package with the standard runtime tools.
prepare_dsm_runtime_fixture
set_mock_dsm_version 7 7.2

# Act: probe compatibility for Docker Engine 27.
probe_output=$(run_runtime_probe 27)

# Expect: DSM 7 and its essential utilities are accepted.
expect_contains "$probe_output" 'DSM major version: 7' 'recognizes DSM 7'
expect_contains "$probe_output" 'OK      DSM 7 synopkg found' 'DSM 7 package tool found'
expect_contains "$probe_output" 'OK      timeout --foreground works' 'GNU timeout works'
expect_contains "$probe_output" 'OK      readlink -f works' 'readlink -f works'
expect_contains "$probe_output" 'OK      realpath works' 'realpath works'
