#!/bin/bash
# AppArmor install, backup, rollback, and restore. Run alone with: bash tests/run.sh apparmor_lifecycle
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture
prepare_installed_files
docker_backup_filename=complete.tgz
execute_backup >/dev/null

# Arrange: redirect kernel/AppArmor paths into disposable fake files.
parser="$test_tmp_dir/apparmor_parser"
enabled="$test_tmp_dir/apparmor-enabled"
profiles="$test_tmp_dir/apparmor-profiles"
apparmor_script="$test_tmp_dir/install_apparmor_profile.sh"
sed -e "s@/usr/sbin/apparmor_parser@$parser@g" -e "s@/sbin/apparmor_parser@$parser@g" \
  -e "s@/sys/module/apparmor/parameters/enabled@$enabled@g" \
  -e "s@/sys/kernel/security/apparmor/profiles@$profiles@g" \
  "$repo_dir/install_apparmor_profile.sh" > "$apparmor_script"
cp /bin/true "$parser"
printf 'Y\n' > "$enabled"
printf 'docker-default (enforce)\n' > "$profiles"
profile="/var/packages/ContainerManager/etc/docker-default.profile"
printf 'unmanaged profile\n' > "$profile"

# Act/expect: an unmanaged profile is never overwritten.
expect_failure 'unmanaged profile prevents installation' bash "$apparmor_script"
expect_files_equal /bin/true "$parser" 'failed install leaves original parser untouched'

# Act/expect: install creates a managed profile and parser wrapper.
rm "$profile"
(command bash "$apparmor_script") >/dev/null
expect_file_exists "$profile" 'managed profile installed'
expect_file_exists "${profile}.synology-docker-managed" 'managed marker installed'
expect_success 'original parser saved as executable' test -x "${parser}.real"
expect_file_contains "$parser" 'Synology DSM apparmor_parser wrapper' 'parser wrapper installed'
(command bash "$apparmor_script") >/dev/null
docker_backup_filename='apparmor-state.tgz'
execute_backup >/dev/null
archive_listing=$(tar -tzf "$test_tmp_dir/apparmor-state.tgz")
expect_contains "$archive_listing" 'docker-default.profile.synology-docker-managed' 'managed marker included in backup'
docker_backup_filename='complete.tgz'
temp_dir=$(mktemp -d)
execute_extract_backup >/dev/null
skip_docker_update='false'
bash() {
  if [[ "$1" = "${SCRIPT_DIR}/install_apparmor_profile.sh" ]]; then
    shift
    command bash "$apparmor_script" "$@"
  else
    command bash "$@"
  fi
}

# Act/expect: restore an archive without AppArmor state; remove managed files.
execute_restore_script >/dev/null
expect_file_absent "$profile" 'restore without AppArmor removes profile'
expect_file_absent "${profile}.synology-docker-managed" 'restore without AppArmor removes marker'
expect_file_absent "${parser}.real" 'restore without AppArmor removes parser backup'
cd "$repo_dir"
rm -rf "$temp_dir"
temp_dir=''

# Act/expect: restore a managed profile from its archive.
docker_backup_filename='apparmor-state.tgz'
temp_dir=$(mktemp -d)
execute_extract_backup >/dev/null
execute_restore_script >/dev/null
unset -f bash
expect_files_equal "$temp_dir/docker-default.profile" "$profile" 'managed profile restored from backup'
expect_file_exists "${profile}.synology-docker-managed" 'managed marker restored'
expect_success 'parser backup restored' test -x "${parser}.real"
cd "$repo_dir"
rm -rf "$temp_dir"
temp_dir=''
bash "$apparmor_script" --restore >/dev/null
expect_file_absent "$profile" 'uninstall removes managed profile'
expect_file_absent "${profile}.synology-docker-managed" 'uninstall removes marker'
expect_file_absent "${parser}.real" 'uninstall removes parser backup'
expect_files_equal /bin/true "$parser" 'uninstall restores parser'
expect_file_lacks "$SYNO_DOCKER_SCRIPT" docker-default.profile 'uninstall removes profile startup entry'

# Act/expect: failed profile load rolls back the partial install.
: > "$profiles"
expect_failure 'failed profile load is rejected' bash "$apparmor_script"
expect_file_absent "$profile" 'failed load removes profile'
expect_file_absent "${profile}.synology-docker-managed" 'failed load removes marker'
expect_file_absent "${parser}.real" 'failed load removes parser backup'
expect_files_equal /bin/true "$parser" 'failed load restores parser'
printf 'AppArmor install, rollback, and restore tests passed\n'
