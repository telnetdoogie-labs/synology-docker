#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/apparmor_fixture.sh
source "$(dirname "$0")/../lib/apparmor_fixture.sh"

# Arrange: a managed AppArmor profile is installed.
prepare_apparmor_fixture
install_managed_apparmor

# Act: uninstall the managed profile.
bash "$apparmor_script" --restore >/dev/null

# Expect: remove managed state, restore the original parser and startup script.
expect_file_absent "$profile" 'uninstall removes managed profile'
expect_file_absent "${profile}.synology-docker-managed" 'uninstall removes marker'
expect_file_absent "${parser}.real" 'uninstall removes parser backup'
expect_files_equal /bin/true "$parser" 'uninstall restores parser'
expect_file_lacks "$SYNO_DOCKER_SCRIPT" docker-default.profile 'uninstall removes profile startup entry'
