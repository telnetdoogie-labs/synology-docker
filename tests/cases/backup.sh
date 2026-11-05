#!/bin/bash
# Backup permissions and incomplete backup rejection. Run alone with: bash tests/run.sh backup
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: install a complete fake DSM package.
init_update_fixture
prepare_installed_files

docker_backup_filename='complete.tgz'

# Act: back up the complete package.
execute_backup >/dev/null

# Expect: a private, nonempty archive; never replace an existing backup.
expect_success 'backup archive is nonempty' test -s "$backup_dir/$docker_backup_filename"
expect_eq 600 "$(stat -c %a "$backup_dir/$docker_backup_filename")" 'backup archive must be owner-only'
expect_failure 'existing backup cannot be overwritten' execute_backup

# Arrange: make the installation incomplete, then try another backup.
rm "$SYNO_DOCKER_JSON"
docker_backup_filename='incomplete.tgz'
expect_failure 'incomplete backup is rejected' execute_backup
expect_file_absent "$backup_dir/$docker_backup_filename" 'failed backup leaves no archive'
printf 'Backup validation tests passed\n'
