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

# Act: consent to installing the logging helper.
printf 'YES\n' | (cd "$logging_dir" && bash "$repo_dir/add_logging_to_start_script.sh") >/dev/null

# Expect: original backed up, replacement installed with executable mode.
expect_files_equal "$test_tmp_dir/start-stop-status.expected" "$logging_dir/start-stop-status.bkup" 'backup contains original script'
expect_files_equal "$repo_dir/test_file/start-stop-status.withlogging" "$SYNO_DOCKER_SCRIPT" 'logging script is installed'
expect_eq 744 "$(stat -c '%a' "$SYNO_DOCKER_SCRIPT")" 'installed script retains executable permissions'
