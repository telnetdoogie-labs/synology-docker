#!/bin/bash
# An update that needs the current Docker or Compose version stops before changing anything when the package is
# stopped and that version can't be detected. Run alone with: bash tests/run.sh updater_rejects_stopped_package_without_versions
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/update_run_fixture.sh
source "$(dirname "$0")/../lib/update_run_fixture.sh"

# Arrange: DSM removes the Docker CLIs from PATH while the package is stopped, so no version is detectable.
init_update_fixture
prepare_installed_files
prepare_update_run_fixture
mock_installed_versions '' '' ''
make_engine_archive 29.0.0 docker dockerd
installed_before=$(installed_file_hashes)

# Each target needs a different current version: Engine and Compose, Engine only, or Compose only.
for update_target in all engine compose; do
  mock_synopkg stopped
  : > "$curl_log"

  # Act: an ordinary update through the real entrypoint.
  update_status=0
  update_output=$(
    main --skip-iptables --path "$test_tmp_dir" --backup "stopped-$update_target.tgz" \
      --docker 29.0.0 --compose 2.42.0 --target "$update_target" update 2>&1
  ) || update_status=$?

  # Expect: a clear refusal with the start command, and nothing started, stopped, downloaded, or backed up.
  expect_eq 1 "$update_status" "target $update_target refuses to update a stopped package"
  expect_contains "$update_output" 'ContainerManager is not running (status: stopped)' \
    "target $update_target explains the package is stopped"
  expect_contains "$update_output" "Start it first with 'sudo synopkg start ContainerManager'" \
    "target $update_target tells the user how to start the package"
  expect_not_contains "$update_output" 'Step 1 from' "target $update_target starts no update step"
  expect_eq status "$(sort -u "$synopkg_log")" "target $update_target only queries the package status"
  expect_eq '' "$(<"$curl_log")" "target $update_target downloads nothing"
  expect_file_absent "$test_tmp_dir/stopped-$update_target.tgz" "target $update_target takes no backup"
  expect_eq "$installed_before" "$(installed_file_hashes)" "target $update_target leaves installed files unchanged"
done
