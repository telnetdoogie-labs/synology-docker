#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture

# Arrange: request an Engine update, but skip Compose.
force='false'
skip_docker_update='false'
skip_compose_update='true'
skip_driver_update='false'

# Act: give an invalid answer, then confirm.
confirm_output=$(confirm_operation <<'EOF'
retry
YES
EOF
)

# Expect: a retry prompt and only the selected component.
expect_contains "$confirm_output" 'Please answer y(es) or n(o)' 'invalid answer prompts again'
expect_contains "$confirm_output" 'Docker Engine' 'engine is listed'
expect_not_contains "$confirm_output" 'Docker Compose' 'skipped Compose is omitted'
