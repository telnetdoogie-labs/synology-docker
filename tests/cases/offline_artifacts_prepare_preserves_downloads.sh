#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: an offline archive is the selected input.
init_update_fixture
mkdir -p "$test_tmp_dir/downloads"
: > "$test_tmp_dir/downloads/docker-28.0.0.tgz"
: > "$test_tmp_dir/downloads/docker-29.0.0.tgz"
download_dir="$test_tmp_dir/downloads"
target_docker_version='29.0.0'
docker_version='29.0.0'
temp_dir=''

# Act: prepare in a private directory, then clean it.
execute_prepare
expect_success 'preparation uses a private directory' test "$temp_dir" != "$download_dir"
expect_file_exists "$download_dir/docker-29.0.0.tgz" 'source archive survives preparation'
execute_clean 'silent'

# Expect: cleanup does not delete the offline source.
expect_file_exists "$download_dir/docker-29.0.0.tgz" 'cleanup preserves offline archive'
