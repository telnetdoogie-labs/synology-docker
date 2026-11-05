#!/bin/bash
# Confirmation prompt rejects no and skips prompt when forced. Run alone with: bash tests/run.sh confirmation
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture

force='false'
skip_docker_update='false'
skip_compose_update='true'
skip_driver_update='false'
confirm_output=$(confirm_operation <<'EOF'
retry
YES
EOF
)
[[ "$confirm_output" == *'Please answer y(es) or n(o)'* ]]
[[ "$confirm_output" == *'Docker Engine'* ]]
[[ "$confirm_output" != *'Docker Compose'* ]]
confirm_sentinel="$test_tmp_dir/confirm-aborted"
(
  confirm_operation <<'EOF'
n
EOF
  : > "$confirm_sentinel"
)
[[ ! -e "$confirm_sentinel" ]]
force='true'
confirm_output=$(confirm_operation </dev/null)
[[ -z "$confirm_output" ]]
force='false'
printf 'Confirmation prompt tests passed\n'
