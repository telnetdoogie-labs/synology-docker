#!/bin/bash
# restore, start, and stop stay usable when the package is stopped and no version can be detected.
# Run alone with: bash tests/run.sh updater_skips_version_detection_for_service_commands
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/update_run_fixture.sh
source "$(dirname "$0")/../lib/update_run_fixture.sh"

# Arrange: a stopped package whose Docker and Compose CLIs are unavailable.
init_update_fixture
prepare_installed_files
prepare_update_run_fixture
mock_installed_versions '' '' ''

# Act/expect: the updater's compatibility gate lets each service command through without a version.
for service_command in restore start stop; do
  mock_synopkg stopped
  command=$service_command
  if ! gate_output=$(detect_current_versions 2>&1); then
    printf 'FAIL: %s is blocked by current-version detection\n%s\n' "$service_command" "$gate_output" >&2
    exit 1
  fi
  expect_contains "$gate_output" 'Current Docker version: Unknown' "$service_command runs with an unknown Docker version"
  expect_eq '' "$(<"$synopkg_log")" "$service_command does not need the package running to pass the gate"
done
command=''

# Act: start the stopped package through the real entrypoint.
mock_synopkg stopped
start_output=$(main start 2>&1)

# Expect: the package is started.
expect_contains "$start_output" 'Done.' 'start completes without a detectable version'
expect_eq started "$(<"$synopkg_state")" 'start brings the package up'

# Act: stop a running package whose CLIs are unavailable, through the real entrypoint.
mock_synopkg started
stop_output=$(main stop 2>&1)

# Expect: the package is stopped.
expect_contains "$stop_output" 'Done.' 'stop completes without a detectable version'
expect_eq stopped "$(<"$synopkg_state")" 'stop takes the package down'
