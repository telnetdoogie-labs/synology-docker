#!/bin/bash
# An ordinary update does not reinstall Engine, Compose, or the log driver when they're already at their targets.
# Run alone with: bash tests/run.sh updater_skips_components_already_at_target
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/update_run_fixture.sh
source "$(dirname "$0")/../lib/update_run_fixture.sh"

# Arrange: Engine, Compose, runc, and the log driver all match the requested targets.
init_update_fixture
prepare_installed_files
prepare_update_run_fixture
mock_synopkg started
mock_installed_versions 29.7.0 2.42.0 1.4.3
set_installed_log_driver local
make_engine_archive 29.7.0 docker dockerd
installed_before=$(installed_file_hashes)

# Act: run an ordinary (unforced) update to the installed versions.
update_status=0
update_output=$(
  main --skip-iptables --path "$test_tmp_dir" --backup current.tgz --docker 29.7.0 --compose 2.42.0 update 2>&1
) || update_status=$?

# Expect: the run stops as already current, before any backup, download, or service change.
expect_eq 1 "$update_status" 'an already-current update does not continue'
expect_contains "$update_output" 'already on target versions' 'the user is told everything is current'
expect_not_contains "$update_output" 'WARNING! This will replace' 'nothing is offered for replacement'
expect_not_contains "$update_output" 'Step 1 from' 'no update step starts'
expect_eq '' "$(<"$curl_log")" 'nothing is downloaded'
expect_file_absent "$test_tmp_dir/current.tgz" 'no backup is taken'
expect_file_lacks "$synopkg_log" stop 'the package is not stopped'
expect_eq "$installed_before" "$(installed_file_hashes)" 'installed files are unchanged'

# Arrange: only Compose is behind its target.
mock_installed_versions 29.7.0 2.40.0 1.4.3

# Act: run the same update and decline at the confirmation prompt.
partial_output=$(
  main --skip-iptables --path "$test_tmp_dir" --backup partial.tgz --docker 29.7.0 --compose 2.42.0 update 2>&1 <<< n
)

# Expect: only the out-of-date component is offered for replacement.
expect_contains "$partial_output" '  - Docker Compose' 'the outdated Compose binary is offered'
expect_not_contains "$partial_output" '  - Docker Engine' 'the current Engine is not reinstalled'
expect_not_contains "$partial_output" '  - Docker daemon log driver' 'the current log driver is not reconfigured'
expect_eq '' "$(<"$curl_log")" 'declining downloads nothing'
