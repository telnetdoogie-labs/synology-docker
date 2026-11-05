#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/apparmor_fixture.sh
source "$(dirname "$0")/../lib/apparmor_fixture.sh"

# Arrange: AppArmor is enabled, but the kernel rejects loading a profile.
prepare_apparmor_fixture
: > "$profiles"

# Act/expect: a failed load is rejected and leaves no managed state behind.
expect_failure 'failed profile load is rejected' bash "$apparmor_script"
expect_file_absent "$profile" 'failed load removes profile'
expect_file_absent "${profile}.synology-docker-managed" 'failed load removes marker'
expect_file_absent "${parser}.real" 'failed load removes parser backup'
expect_files_equal /bin/true "$parser" 'failed load restores parser'
