#!/bin/bash
# restore without --backup NAME fails clearly before stopping Docker or changing installed files.
# Run alone with: bash tests/run.sh restore_requires_backup_name
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/update_run_fixture.sh
source "$(dirname "$0")/../lib/update_run_fixture.sh"

# Arrange: a running package and installed files to compare against.
init_update_fixture
prepare_installed_files
prepare_update_run_fixture
mock_installed_versions 29.0.0 2.42.0 1.4.3
installed_before=$(installed_file_hashes)

# Each variant: the restore arguments, and the error the user must see.
restore_variants=(
  'restore|Please specify backup filename (--backup NAME)'
  'restore --backup|Filename not provided'
  '--backup --force restore|Filename not provided'
)
for variant in "${restore_variants[@]}"; do
  IFS='|' read -r restore_args expected_error <<< "$variant"
  mock_synopkg started
  read -r -a restore_argv <<< "$restore_args"

  # Act: run restore through the real entrypoint, answering yes if asked to confirm.
  restore_status=0
  restore_output=$(main "${restore_argv[@]}" 2>&1 <<< y) || restore_status=$?

  # Expect: a clear failure, with Docker left running and untouched.
  expect_eq 1 "$restore_status" "'$restore_args' fails"
  expect_contains "$restore_output" "$expected_error" "'$restore_args' says the backup name is missing"
  expect_not_contains "$restore_output" 'Extracting Docker backup' "'$restore_args' extracts nothing"
  expect_file_lacks "$synopkg_log" stop "'$restore_args' does not stop the package"
  expect_eq "$installed_before" "$(installed_file_hashes)" "'$restore_args' leaves installed files unchanged"
done
