#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: installed script has no logging, replacement is available.
init_update_fixture
prepare_installed_files
logging_dir="$test_tmp_dir/add-logging"
mkdir -p "$logging_dir/test_file"
cp "$repo_dir/test_file/start-stop-status.withlogging" "$logging_dir/test_file/start-stop-status.withlogging"
cp "$repo_dir/test_file/start-stop-status" "$SYNO_DOCKER_SCRIPT"
cp "$SYNO_DOCKER_SCRIPT" "$test_tmp_dir/start-stop-status.expected"

# Act: reject the proposed logging change.
printf 'n\n' | (cd "$logging_dir" && bash "$repo_dir/add_logging_to_start_script.sh") >/dev/null

# Expect: no backup and no change to the installed script.
expect_file_absent "$logging_dir/start-stop-status.bkup" 'cancellation creates no backup'
expect_files_equal "$test_tmp_dir/start-stop-status.expected" "$SYNO_DOCKER_SCRIPT" 'cancellation preserves startup script'
