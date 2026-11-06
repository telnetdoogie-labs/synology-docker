#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: offline archives contain Engine 28 and 29.
init_update_fixture
mkdir -p "$test_tmp_dir/downloads"
: > "$test_tmp_dir/downloads/docker-28.0.0.tgz"
: > "$test_tmp_dir/downloads/docker-29.0.0.tgz"
download_dir="$test_tmp_dir/downloads"
target_docker_version=''

# Act: detect available local downloads.
detect_available_downloads

# Expect: select the newest offline Engine archive.
expect_eq 29.0.0 "$target_docker_version" 'latest offline engine is chosen'
