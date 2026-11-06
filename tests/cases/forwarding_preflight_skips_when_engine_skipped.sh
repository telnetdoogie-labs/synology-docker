#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: the installed startup script lacks a forwarding anchor.
init_update_fixture
prepare_installed_files
printf '#!/bin/sh\n' > "$SYNO_DOCKER_SCRIPT"
skip_docker_update='true'
command='update'

# Act: skip the engine update.
validate_forwarding_anchor
execute_update_script >/dev/null

# Expect: no unsafe forwarding edit.
expect_eq 1 "$(wc -l < "$SYNO_DOCKER_SCRIPT")" 'skip update leaves script unchanged'
