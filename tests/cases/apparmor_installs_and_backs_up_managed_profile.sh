#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/apparmor_fixture.sh
source "$(dirname "$0")/../lib/apparmor_fixture.sh"

# Arrange: no profile exists, and AppArmor is enabled.
prepare_apparmor_fixture

# Act: install twice, then back up the managed state.
install_managed_apparmor
install_managed_apparmor
docker_backup_filename='apparmor-state.tgz'
execute_backup >/dev/null

# Expect: managed profile, parser wrapper, and backup marker.
expect_file_exists "$profile" 'managed profile installed'
expect_file_exists "${profile}.synology-docker-managed" 'managed marker installed'
expect_success 'original parser saved as executable' test -x "${parser}.real"
expect_file_contains "$parser" 'Synology DSM apparmor_parser wrapper' 'parser wrapper installed'
archive_listing=$(tar -tzf "$test_tmp_dir/apparmor-state.tgz")
expect_contains "$archive_listing" 'docker-default.profile.synology-docker-managed' 'managed marker included in backup'
