#!/bin/bash
# The updater must not install Docker 24+ on an aufs daemon without an explicit override.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: an aufs installation targeting a Docker Engine version that removed aufs.
init_update_fixture
jq '.["storage-driver"] = "aufs"' "$SYNO_DOCKER_JSON" > "$test_tmp_dir/aufs.json"
cp "$test_tmp_dir/aufs.json" "$SYNO_DOCKER_JSON"
target_docker_version='29.0.0'
force='false'
skip_docker_update='false'

# Act: ask the updater to validate its storage-driver transition.
if output=$(define_storage_driver 2>&1); then
  printf 'FAIL: updater accepted Docker 29 with aufs without --force\n' >&2
  exit 1
fi

# Expect: the failure identifies the incompatible driver and leaves its config.
expect_contains "$output" "can't use the 'aufs' storage driver" 'updater blocks incompatible aufs engine'
expect_files_equal "$test_tmp_dir/aufs.json" "$SYNO_DOCKER_JSON" 'failed validation preserves daemon config'
