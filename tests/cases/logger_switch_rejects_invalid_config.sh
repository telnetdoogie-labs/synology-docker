#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: invalid JSON must remain intact after a failed logger switch.
init_update_fixture
logger_json="$test_tmp_dir/dockerd-switch.json"
printf '{invalid\n' > "$logger_json"

# Act/expect: reject invalid input without rewriting it.
expect_failure 'invalid JSON is rejected' sh "$repo_dir/syno_docker_switch_logger.sh" "$logger_json"
expect_eq '{invalid' "$(<"$logger_json")" 'invalid input is left untouched'

# Act/expect: a missing config is also rejected.
expect_failure 'missing JSON is rejected' sh "$repo_dir/syno_docker_switch_logger.sh" "$test_tmp_dir/missing.json"
