#!/bin/bash
# A --backup NAME that includes a path is split into its absolute directory and filename, and restore uses that
# archive. Run alone with: bash tests/run.sh restore_backup_name_with_path
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/update_run_fixture.sh
source "$(dirname "$0")/../lib/update_run_fixture.sh"

init_update_fixture
prepare_installed_files
prepare_update_run_fixture
work_dir=$(readlink -f "$test_tmp_dir")
archive_dir="$work_dir/archive dir"
mkdir -p "$archive_dir"
cd "$work_dir"

# Act/expect: names with a directory become an absolute directory plus a bare filename.
for backup_name in "$archive_dir/nightly.tgz" 'archive dir/nightly.tgz' 'archive dir/../archive dir/nightly.tgz'; do
  backup_dir=/unchanged
  docker_backup_filename=$backup_name
  validate_backup_filename 'Filename not provided'
  expect_eq "$archive_dir" "$backup_dir" "'$backup_name' sets the backup directory"
  expect_eq nightly.tgz "$docker_backup_filename" "'$backup_name' keeps only the filename"
done

# Act/expect: a bare name keeps the --path directory.
backup_dir=/unchanged
docker_backup_filename=nightly.tgz
validate_backup_filename 'Filename not provided'
expect_eq /unchanged "$backup_dir" 'a bare name keeps the backup directory'
expect_eq nightly.tgz "$docker_backup_filename" 'a bare name is unchanged'

# Act/expect: a directory that doesn't exist is reported, not replaced with the working directory.
missing_status=0
missing_output=$(
  docker_backup_filename="$work_dir/missing/nightly.tgz"
  validate_backup_filename 'Filename not provided' 2>&1
) || missing_status=$?
expect_eq 1 "$missing_status" 'a missing backup directory is rejected'
expect_contains "$missing_output" "Backup directory not found: $work_dir/missing" 'the missing directory is named'

# Arrange: back up the installed files into the subdirectory, then change the installed Engine.
mock_synopkg started
mock_installed_versions 29.0.0 2.42.0 1.4.3
backup_dir=$archive_dir
docker_backup_filename=nightly.tgz
execute_backup >/dev/null
installed_backup=$(installed_file_hashes)
printf 'changed binary\n' > "$SYNO_DOCKER_BIN/docker"
bash() {
  if [[ "$1" = "$SCRIPT_DIR/install_apparmor_profile.sh" ]]; then
    return 0
  fi
  command bash "$@"
}

# Act: restore through the real entrypoint, naming the archive by its relative path.
restore_output=$(main --backup 'archive dir/nightly.tgz' restore 2>&1 <<< y)

# Expect: the archive in that directory is used and the installed files match it again.
expect_contains "$restore_output" "Extracting Docker backup ($archive_dir/nightly.tgz)" 'restore reads the named archive'
expect_contains "$restore_output" 'Done.' 'restore completes'
expect_eq "$installed_backup" "$(installed_file_hashes)" 'installed files match the backup'
expect_eq started "$(<"$synopkg_state")" 'the package is started again'
