#!/bin/bash
# Confirmation prompt rejects no and skips prompt when forced. Run alone with: bash tests/run.sh confirmation
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: request an engine update, but not a Compose update.
init_update_fixture

force='false'
skip_docker_update='false'
skip_compose_update='true'
skip_driver_update='false'

# Act: give an invalid response, then confirm.
confirm_output=$(confirm_operation <<'EOF'
retry
YES
EOF
)

# Expect: retry guidance and only the selected component.
expect_contains "$confirm_output" 'Please answer y(es) or n(o)' 'invalid answer prompts again'
expect_contains "$confirm_output" 'Docker Engine' 'engine is listed'
expect_not_contains "$confirm_output" 'Docker Compose' 'skipped Compose is omitted'

# Act: decline; the operation must exit before reaching the sentinel.
confirm_sentinel="$test_tmp_dir/confirm-aborted"
(
  confirm_operation <<'EOF'
n
EOF
  : > "$confirm_sentinel"
)
expect_file_absent "$confirm_sentinel" 'declining aborts the operation'

# Act/expect: --force bypasses the prompt even without stdin.
force='true'
confirm_output=$(confirm_operation </dev/null)
expect_eq '' "$confirm_output" 'forced update does not prompt'
force='false'
printf 'Confirmation prompt tests passed\n'
