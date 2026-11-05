#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: a full engine update has no safe startup-script anchor.
init_update_fixture
prepare_installed_files
printf '#!/bin/sh\n' > "$SYNO_DOCKER_SCRIPT"
skip_docker_update='false'
command=''

# Act/expect: reject the update without changing the script.
expect_failure 'full update requires forwarding anchor' execute_update_script
expect_eq 1 "$(wc -l < "$SYNO_DOCKER_SCRIPT")" 'failed update leaves script unchanged'
