#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: a complete archive, then change the installed engine binary.
init_update_fixture
prepare_installed_files
docker_backup_filename='complete.tgz'
execute_backup >/dev/null
skip_docker_update='false'
skip_compose_update='false'
skip_driver_update='false'
stage='false'
temp_dir=$(mktemp -d)
execute_extract_backup >/dev/null
printf 'changed binary\n' > "$SYNO_DOCKER_BIN/docker"

# Act: restore binaries, logger config, and startup script.
execute_restore_bin >/dev/null
execute_restore_log >/dev/null
execute_restore_script >/dev/null

# Expect: each installed file matches the backup.
expect_files_equal "$temp_dir/docker/docker" "$SYNO_DOCKER_BIN/docker" 'engine binary restored'
expect_files_equal "$temp_dir/dockerd.json" "$SYNO_DOCKER_JSON" 'daemon config restored'
expect_files_equal "$temp_dir/start-stop-status" "$SYNO_DOCKER_SCRIPT" 'startup script restored'
cd "$repo_dir"
rm -rf "$temp_dir"
temp_dir=''
