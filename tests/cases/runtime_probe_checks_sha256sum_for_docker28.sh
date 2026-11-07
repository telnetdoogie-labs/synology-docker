#!/bin/bash
# Docker Engine 28+ downloads kernel modules, which are verified with sha256sum.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/dsm_runtime_fixture.sh
source "$(dirname "$0")/../lib/dsm_runtime_fixture.sh"

# Arrange: a DSM 7 environment where sha256sum is available.
prepare_dsm_runtime_fixture
set_mock_dsm_version 7 7.2

# Act: probe for Engine 27, which needs no modules, and for Engine 28.
legacy_output=$(run_runtime_probe 27 2>&1 || true)
probe_output=$(run_runtime_probe 28 2>&1 || true)

# Expect: only the Engine 28 probe checks for sha256sum.
expect_not_contains "$legacy_output" 'sha256sum' 'Engine 27 does not check sha256sum'
expect_contains "$probe_output" 'OK      sha256sum' 'Engine 28 checks sha256sum'
