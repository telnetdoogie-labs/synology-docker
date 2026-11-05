#!/bin/bash
# Offline artifact selection and disposable prepare directory. Run alone with: bash tests/run.sh offline_artifacts
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture

mkdir -p "$test_tmp_dir/downloads"
: > "$test_tmp_dir/downloads/docker-28.0.0.tgz"
: > "$test_tmp_dir/downloads/docker-29.0.0.tgz"
download_dir="$test_tmp_dir/downloads"
target_docker_version=''
detect_available_downloads
[[ "$target_docker_version" == '29.0.0' ]]
docker_version='100.0.0'
force='false'
if (validate_offline_target) >/dev/null 2>&1; then
  printf 'Offline Docker downgrade unexpectedly succeeded\n' >&2
  exit 1
fi
force='true'
validate_offline_target
docker_version='29.0.0'
temp_dir=''
execute_prepare
[[ "$temp_dir" != "$download_dir" && -f "$download_dir/docker-29.0.0.tgz" ]]
execute_clean 'silent'
[[ -f "$download_dir/docker-29.0.0.tgz" ]]
printf 'Offline input and private temp directory tests passed\n'
