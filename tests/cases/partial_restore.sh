#!/bin/bash
# Partial restore must preserve the engine startup script. Run alone with: bash tests/run.sh partial_restore
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: place a different startup script in a backup.
init_update_fixture
prepare_installed_files

temp_dir=$(mktemp -d)
printf 'backup script\n' > "$temp_dir/start-stop-status"
skip_docker_update='true'
script_before=$(sha256sum "$SYNO_DOCKER_SCRIPT")

# Act: restore only the non-engine components.
execute_restore_script >/dev/null

# Expect: the installed engine startup script is unchanged.
expect_eq "$script_before" "$(sha256sum "$SYNO_DOCKER_SCRIPT")" 'partial restore preserves startup script'
rm -rf "$temp_dir"
temp_dir=''
printf 'Partial restore preserves the engine startup script\n'
