#!/bin/bash
# Redirect AppArmor's kernel/parser paths into disposable test files.
# Source only after test_env.sh has checked the test-image guard.
# shellcheck disable=SC2154,SC2034

prepare_apparmor_fixture() {
  init_update_fixture
  prepare_installed_files

  parser="$test_tmp_dir/apparmor_parser"
  enabled="$test_tmp_dir/apparmor-enabled"
  profiles="$test_tmp_dir/apparmor-profiles"
  apparmor_script="$test_tmp_dir/install_apparmor_profile.sh"
  profile='/var/packages/ContainerManager/etc/docker-default.profile'

  sed -e "s@/usr/sbin/apparmor_parser@$parser@g" -e "s@/sbin/apparmor_parser@$parser@g" \
    -e "s@/sys/module/apparmor/parameters/enabled@$enabled@g" \
    -e "s@/sys/kernel/security/apparmor/profiles@$profiles@g" \
    "$repo_dir/install_apparmor_profile.sh" > "$apparmor_script"
  cp /bin/true "$parser"
  printf 'Y\n' > "$enabled"
  printf 'docker-default (enforce)\n' > "$profiles"
}

install_managed_apparmor() {
  command bash "$apparmor_script" >/dev/null
}
