#!/bin/bash
# Standalone logging helper cancellation and backup. Run alone with: bash tests/run.sh logging_helper
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: an installed script without logging and a replacement with logging.
init_update_fixture
prepare_installed_files

logging_dir="$test_tmp_dir/add-logging"
mkdir -p "$logging_dir/test_file"
cp "$repo_dir/test_file/start-stop-status.withlogging" "$logging_dir/test_file/start-stop-status.withlogging"
cp "$repo_dir/test_file/start-stop-status" "$SYNO_DOCKER_SCRIPT"
cp "$SYNO_DOCKER_SCRIPT" "$test_tmp_dir/start-stop-status.expected"

# Act/expect: cancellation leaves the script untouched and creates no backup.
printf 'n\n' | (cd "$logging_dir" && bash "$repo_dir/add_logging_to_start_script.sh") >/dev/null
expect_file_absent "$logging_dir/start-stop-status.bkup" 'cancellation creates no backup'
expect_files_equal "$test_tmp_dir/start-stop-status.expected" "$SYNO_DOCKER_SCRIPT" 'cancellation preserves startup script'

# Act/expect: consent installs logging and keeps the original as a backup.
printf 'YES\n' | (cd "$logging_dir" && bash "$repo_dir/add_logging_to_start_script.sh") >/dev/null
expect_files_equal "$test_tmp_dir/start-stop-status.expected" "$logging_dir/start-stop-status.bkup" 'backup contains original script'
expect_files_equal "$repo_dir/test_file/start-stop-status.withlogging" "$SYNO_DOCKER_SCRIPT" 'logging script is installed'
expect_eq 744 "$(stat -c '%a' "$SYNO_DOCKER_SCRIPT")" 'installed script retains executable permissions'
printf 'Standalone logging helper tests passed\n'
