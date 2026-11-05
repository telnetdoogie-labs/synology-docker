#!/bin/bash
# Partial restore must preserve the engine startup script. Run alone with: bash tests/run.sh partial_restore
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture
prepare_installed_files

temp_dir=$(mktemp -d)
printf 'backup script\n' > "$temp_dir/start-stop-status"
skip_docker_update='true'
script_before=$(sha256sum "$SYNO_DOCKER_SCRIPT")
execute_restore_script >/dev/null
[[ $(sha256sum "$SYNO_DOCKER_SCRIPT") == "$script_before" ]]
rm -rf "$temp_dir"
temp_dir=''
printf 'Partial restore preserves the engine startup script\n'
