#!/bin/bash
# AppArmor install, backup, rollback, and restore. Run alone with: bash tests/run.sh apparmor_lifecycle
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture
prepare_installed_files
docker_backup_filename=complete.tgz
execute_backup >/dev/null

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
if (bash "$apparmor_script") >/dev/null 2>&1; then
  printf 'Unmanaged AppArmor profile was overwritten\n' >&2
  exit 1
fi
cmp -s /bin/true "$parser"
rm "$profile"
(command bash "$apparmor_script") >/dev/null
[[ -f "$profile" && -f "${profile}.synology-docker-managed" && -x "${parser}.real" ]]
grep -q 'Synology DSM apparmor_parser wrapper' "$parser"
(command bash "$apparmor_script") >/dev/null
docker_backup_filename='apparmor-state.tgz'
execute_backup >/dev/null
tar -tzf "$test_tmp_dir/apparmor-state.tgz" | grep -q 'docker-default.profile.synology-docker-managed'
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
execute_restore_script >/dev/null
[[ ! -e "$profile" && ! -e "${profile}.synology-docker-managed" && ! -e "${parser}.real" ]]
cd "$repo_dir"
rm -rf "$temp_dir"
temp_dir=''
docker_backup_filename='apparmor-state.tgz'
temp_dir=$(mktemp -d)
execute_extract_backup >/dev/null
execute_restore_script >/dev/null
unset -f bash
cmp -s "$temp_dir/docker-default.profile" "$profile"
[[ -f "${profile}.synology-docker-managed" && -x "${parser}.real" ]]
cd "$repo_dir"
rm -rf "$temp_dir"
temp_dir=''
bash "$apparmor_script" --restore >/dev/null
[[ ! -e "$profile" && ! -e "${profile}.synology-docker-managed" && ! -e "${parser}.real" ]]
cmp -s /bin/true "$parser"
if grep -q 'docker-default.profile' "$SYNO_DOCKER_SCRIPT"; then
  printf 'Unmanaged AppArmor profile entry remained in startup script\n' >&2
  exit 1
fi
: > "$profiles"
if (bash "$apparmor_script") >/dev/null 2>&1; then
  printf 'Failed AppArmor profile load was accepted\n' >&2
  exit 1
fi
[[ ! -e "$profile" && ! -e "${profile}.synology-docker-managed" && ! -e "${parser}.real" ]]
cmp -s /bin/true "$parser"
printf 'AppArmor install, rollback, and restore tests passed\n'
