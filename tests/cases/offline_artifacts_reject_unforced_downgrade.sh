#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: installed Engine 100 is newer than the offline target.
init_update_fixture
mkdir -p "$test_tmp_dir/downloads"
: > "$test_tmp_dir/downloads/docker-28.0.0.tgz"
: > "$test_tmp_dir/downloads/docker-29.0.0.tgz"
download_dir="$test_tmp_dir/downloads"
docker_version='100.0.0'
target_docker_version='29.0.0'
force='false'

# Act/expect: downgrade needs explicit force.
expect_failure 'offline downgrade needs force' validate_offline_target
force='true'
validate_offline_target
