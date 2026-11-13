#!/bin/bash
# An update stops before replacing binaries when the package reports stopped but dockerd is still running, or
# when the stop times out. Run alone with: bash tests/run.sh service_stop_incomplete_preserves_binaries
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/update_run_fixture.sh
source "$(dirname "$0")/../lib/update_run_fixture.sh"

# Arrange: a complete Engine archive, and a clock that passes five minutes per reading so the
# ten-minute stop timeout is reached after a few polls without waiting.
init_update_fixture
prepare_installed_files
prepare_update_run_fixture
mock_installed_versions 28.0.0 2.42.0 1.1.0
make_engine_archive 29.0.0 docker dockerd containerd runc
installed_before=$(installed_file_hashes)
clock_file="$test_tmp_dir/clock"
date() {
  if [[ "$1" = +%s ]]; then
    local now
    now=$(<"$clock_file")
    printf '%s\n' "$now"
    printf '%s\n' "$((now + 300))" > "$clock_file"
  else
    command date "$@"
  fi
}
sleep() { :; }

# Each variant: status left after 'stop', whether dockerd keeps running, and the expected error.
stop_variants=(
  'stopped|true|ContainerManager reports stopped, but dockerd is still running'
  'stopping|false|Timed out stopping Docker (status: stopping)'
)
for variant in "${stop_variants[@]}"; do
  IFS='|' read -r status_after_stop dockerd_still_running expected_error <<< "$variant"
  mock_synopkg started "$status_after_stop"
  mock_dockerd_running "$dockerd_still_running"
  printf '1000\n' > "$clock_file"

  # Act: update the Engine through the real entrypoint.
  update_status=0
  update_output=$(
    main --force --skip-iptables --path "$test_tmp_dir" --backup "stop-$status_after_stop.tgz" \
      --docker 29.0.0 --target engine update 2>&1
  ) || update_status=$?

  # Expect: the stop is reported as incomplete and no installed binary is replaced.
  expect_eq 1 "$update_status" "incomplete stop ($status_after_stop) fails the update"
  expect_contains "$update_output" "$expected_error" "incomplete stop ($status_after_stop) names the cause"
  expect_contains "$update_output" 'The Docker binaries have not been replaced.' \
    "incomplete stop ($status_after_stop) tells the user nothing was replaced"
  expect_contains "$update_output" "Docker service may be stopped. Backup: $test_tmp_dir/stop-$status_after_stop.tgz" \
    "incomplete stop ($status_after_stop) points to the backup"
  expect_file_contains "$synopkg_log" stop "incomplete stop ($status_after_stop) did ask the package to stop"
  expect_not_contains "$update_output" 'Installing binaries' "incomplete stop ($status_after_stop) does not reach installation"
  expect_eq "$installed_before" "$(installed_file_hashes)" "incomplete stop ($status_after_stop) leaves installed files unchanged"
done
