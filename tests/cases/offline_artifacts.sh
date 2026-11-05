#!/bin/bash
# Offline artifact selection and disposable prepare directory. Run alone with: bash tests/run.sh offline_artifacts
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture

# Arrange: two local engine archives, with no network lookup.
mkdir -p "$test_tmp_dir/downloads"
: > "$test_tmp_dir/downloads/docker-28.0.0.tgz"
: > "$test_tmp_dir/downloads/docker-29.0.0.tgz"
download_dir="$test_tmp_dir/downloads"
target_docker_version=''

# Act/expect: choose the newest available archive.
detect_available_downloads
expect_eq 29.0.0 "$target_docker_version" 'latest offline engine is chosen'

# Act/expect: reject an implicit downgrade, allow explicit force.
docker_version='100.0.0'
force='false'
expect_failure 'offline downgrade needs force' validate_offline_target
force='true'
validate_offline_target
docker_version='29.0.0'
temp_dir=''

# Act/expect: preparation uses a private directory and preserves source archives.
execute_prepare
expect_success 'preparation uses a private directory' test "$temp_dir" != "$download_dir"
expect_file_exists "$download_dir/docker-29.0.0.tgz" 'source archive survives preparation'
execute_clean 'silent'
expect_file_exists "$download_dir/docker-29.0.0.tgz" 'cleanup preserves offline archive'
printf 'Offline input and private temp directory tests passed\n'
