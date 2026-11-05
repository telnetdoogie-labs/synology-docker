#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture

# Arrange: an unforced update requests confirmation.
force='false'
skip_docker_update='false'
skip_compose_update='true'
skip_driver_update='false'
confirm_sentinel="$test_tmp_dir/confirm-aborted"

# Act: decline; the operation must exit before writing the sentinel.
(
  confirm_operation <<'EOF'
n
EOF
  : > "$confirm_sentinel"
)

# Expect: the declined operation never continues.
expect_file_absent "$confirm_sentinel" 'declining aborts the operation'
