#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/apparmor_fixture.sh
source "$(dirname "$0")/../lib/apparmor_fixture.sh"

# Arrange: keep an archive before and after installing a managed profile.
prepare_apparmor_fixture
docker_backup_filename='complete.tgz'
execute_backup >/dev/null
install_managed_apparmor
docker_backup_filename='apparmor-state.tgz'
execute_backup >/dev/null
skip_docker_update='false'

# The updater invokes the installed AppArmor script by its normal path;
# route only that call to the path-redirected test copy.
# shellcheck disable=SC2329 # Called indirectly by execute_restore_script.
bash() {
  if [[ "$1" = "${SCRIPT_DIR}/install_apparmor_profile.sh" ]]; then
    shift
    command bash "$apparmor_script" "$@"
  else
    command bash "$@"
  fi
}

# Act: restoring the older archive removes the now-managed profile.
docker_backup_filename='complete.tgz'
temp_dir=$(mktemp -d)
execute_extract_backup >/dev/null
execute_restore_script >/dev/null
expect_file_absent "$profile" 'restore without AppArmor removes profile'
expect_file_absent "${profile}.synology-docker-managed" 'restore without AppArmor removes marker'
expect_file_absent "${parser}.real" 'restore without AppArmor removes parser backup'
cd "$repo_dir"
rm -rf "$temp_dir"
temp_dir=''

# Act: restoring the later archive reinstates the managed state.
docker_backup_filename='apparmor-state.tgz'
temp_dir=$(mktemp -d)
execute_extract_backup >/dev/null
execute_restore_script >/dev/null
unset -f bash

# Expect: the profile and parser backup match the saved state.
expect_files_equal "$temp_dir/docker-default.profile" "$profile" 'managed profile restored from backup'
expect_file_exists "${profile}.synology-docker-managed" 'managed marker restored'
expect_success 'parser backup restored' test -x "${parser}.real"
cd "$repo_dir"
rm -rf "$temp_dir"
temp_dir=''
