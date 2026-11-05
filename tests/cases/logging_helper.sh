#!/bin/bash
# Standalone logging helper cancellation and backup. Run alone with: bash tests/run.sh logging_helper
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture
prepare_installed_files

logging_dir="$test_tmp_dir/add-logging"
mkdir -p "$logging_dir/test_file"
cp "$repo_dir/test_file/start-stop-status.withlogging" "$logging_dir/test_file/start-stop-status.withlogging"
cp "$repo_dir/test_file/start-stop-status" "$SYNO_DOCKER_SCRIPT"
cp "$SYNO_DOCKER_SCRIPT" "$test_tmp_dir/start-stop-status.expected"
printf 'n\n' | (cd "$logging_dir" && bash "$repo_dir/add_logging_to_start_script.sh") >/dev/null
[[ ! -e "$logging_dir/start-stop-status.bkup" ]]
cmp -s "$test_tmp_dir/start-stop-status.expected" "$SYNO_DOCKER_SCRIPT"
printf 'YES\n' | (cd "$logging_dir" && bash "$repo_dir/add_logging_to_start_script.sh") >/dev/null
cmp -s "$test_tmp_dir/start-stop-status.expected" "$logging_dir/start-stop-status.bkup"
cmp -s "$repo_dir/test_file/start-stop-status.withlogging" "$SYNO_DOCKER_SCRIPT"
[[ $(stat -c '%a' "$SYNO_DOCKER_SCRIPT") == '744' ]]
printf 'Standalone logging helper tests passed\n'
