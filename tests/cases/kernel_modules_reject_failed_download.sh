#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/kernel_modules_fixture.sh
source "$(dirname "$0")/../lib/kernel_modules_fixture.sh"

# Arrange: curl cannot download either module.
prepare_kernel_modules_fixture
# shellcheck disable=SC2329 # Called by download_and_place_modules through expect_failure.
curl() { return 1; }

# Act/expect: do not report a failed download as a successful install.
expect_failure 'failed module download is rejected' download_and_place_modules
