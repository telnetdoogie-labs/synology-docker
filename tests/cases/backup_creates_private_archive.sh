#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: install a complete fake DSM package.
init_update_fixture
prepare_installed_files
docker_backup_filename='complete.tgz'

# Act: back up the package.
execute_backup >/dev/null

# Expect: an owner-only, nonempty archive.
expect_success 'backup archive is nonempty' test -s "$backup_dir/$docker_backup_filename"
expect_eq 600 "$(stat -c %a "$backup_dir/$docker_backup_filename")" 'backup archive must be owner-only'
