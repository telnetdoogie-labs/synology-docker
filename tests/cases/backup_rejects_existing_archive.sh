#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: the desired backup filename already exists.
init_update_fixture
prepare_installed_files
docker_backup_filename='complete.tgz'
execute_backup >/dev/null

# Act/expect: do not overwrite the existing archive.
expect_failure 'existing backup cannot be overwritten' execute_backup
