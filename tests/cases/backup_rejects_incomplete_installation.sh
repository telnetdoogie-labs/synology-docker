#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: the installed daemon config is missing.
init_update_fixture
prepare_installed_files
rm "$SYNO_DOCKER_JSON"
docker_backup_filename='incomplete.tgz'

# Act/expect: do not leave a partial backup.
expect_failure 'incomplete backup is rejected' execute_backup
expect_file_absent "$backup_dir/$docker_backup_filename" 'failed backup leaves no archive'
