#!/bin/bash
# A Docker 28+ update stops before the backup or any download when the iptables modules can't be obtained.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: a copy of the scripts whose module installer reports the modules unavailable and logs its arguments.
work_repo="$test_tmp_dir/repo"
mkdir -p "$work_repo"
cp -a "$repo_dir"/. "$work_repo"
rm -rf "$work_repo/.git"
module_log="$test_tmp_dir/modules.log"
cat > "$work_repo/install_iptables_modules.sh" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >> "$module_log"
echo "   The kernel modules for your platform and kernel are not available for download."
exit 1
STUB
chmod +x "$work_repo/install_iptables_modules.sh"
repo_dir=$work_repo
init_update_fixture
prepare_installed_files
mkdir -p /etc.defaults
printf 'majorversion="7"\nproductversion="7.2"\n' > /etc.defaults/VERSION
printf '#!/bin/sh\necho started\n' > /usr/syno/bin/synopkg
chmod +x /usr/syno/bin/synopkg
curl_log="$test_tmp_dir/curl.log"
: > "$curl_log"

# Act: update to Docker 29 without --skip-iptables.
update_status=0
update_output=$(
  docker() {
    case "$1" in
      ps) return 0 ;;
      -v) printf 'Docker version 27.5.1, build test\n' ;;
      *) return 1 ;;
    esac
  }
  docker-compose() { printf 'Docker Compose version v2.1.1\n'; }
  containerd() { printf 'containerd containerd.io v1.7.0\n'; }
  runc() { printf 'runc version 1.1.0\n'; }
  curl() { printf '%s\n' "$*" >> "$curl_log"; return 22; }
  main --force --path "$test_tmp_dir" --backup modules-check.tgz --docker 29.0.0 --compose 2.42.0 update 2>&1
) || update_status=$?

# Expect: the read-only check ran and stopped the update before anything was downloaded or backed up.
expect_eq 1 "$update_status" 'update fails when modules are unavailable'
expect_eq '--check' "$(<"$module_log")" 'module installer is only asked to check'
expect_contains "$update_output" 'not available for download' 'the module explanation is shown'
expect_contains "$update_output" 'Nothing was downloaded or changed' 'the update says nothing changed'
expect_not_contains "$update_output" 'Step 1 from' 'no update step starts'
expect_eq '' "$(<"$curl_log")" 'nothing is downloaded'
expect_file_absent "$test_tmp_dir/modules-check.tgz" 'no backup is taken'

# Expect: the check is skipped when modules aren't needed or the run is staged.
: > "$module_log"
install_iptables_modules='false' stage='false' validate_iptables_modules
install_iptables_modules='true' stage='true' validate_iptables_modules
expect_eq '' "$(<"$module_log")" 'check is skipped when modules are not needed or the run is staged'
