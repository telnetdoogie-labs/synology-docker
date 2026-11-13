#!/bin/bash
# Docker 29.7.0+ at its target is reinstalled only when an older runc is still installed, so the bundled runc
# replaces it. Run alone with: bash tests/run.sh updater_refreshes_stale_runc_at_target
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

init_update_fixture
prepare_installed_files
config_temp="$test_tmp_dir/dockerd.json.new"
jq '.["log-driver"] = "local"' "$SYNO_DOCKER_JSON" > "$config_temp"
mv "$config_temp" "$SYNO_DOCKER_JSON"

# Plans an ordinary update where Engine, Compose, and the log driver already match their targets.
plan_current_update() {
  force='false'
  docker_version=$1
  target_docker_version=$1
  runc_version=$2
  compose_version='2.42.0'
  target_compose_version='2.42.0'
  skip_docker_update='false'
  skip_compose_update='false'
  skip_driver_update='false'
  skip_iptables_modules='true'
  refresh_runc='false'
  total_steps=10
}

# Arrange: Docker 29.7.0 is at its target, but runc predates the version it bundles.
for stale_runc in 1.1.0 1.4.0; do
  plan_current_update 29.7.0 "$stale_runc"
  plan_output="$test_tmp_dir/plan-$stale_runc.txt"

  # Act: plan the update with the production policy.
  define_update > "$plan_output"

  # Expect: only the Engine is reinstalled, and the user is told why.
  expect_eq true "$refresh_runc" "runc $stale_runc is flagged for refresh"
  expect_eq false "$skip_docker_update" "runc $stale_runc keeps the Engine reinstall"
  expect_eq true "$skip_compose_update" "runc $stale_runc does not reinstall current Compose"
  expect_eq true "$skip_driver_update" "runc $stale_runc does not reconfigure the current log driver"
  expect_file_contains "$plan_output" "runc $stale_runc is older than the version bundled with Docker 29.7.0" \
    "runc $stale_runc reinstall is explained"
  confirm_output=$(confirm_operation <<< n)
  expect_contains "$confirm_output" '  - Docker Engine' "runc $stale_runc offers the Engine for replacement"
  expect_not_contains "$confirm_output" '  - Docker Compose' "runc $stale_runc does not offer Compose"
done

# Act/expect: no refresh when runc is current, unknown, or the target predates the bundled runc.
for no_refresh in '29.7.0 1.4.3' '29.7.0 ' '29.6.1 1.1.0'; do
  read -r current_docker current_runc <<< "$no_refresh"
  plan_current_update "$current_docker" "$current_runc"
  plan_status=0
  plan_output=$(define_update 2>&1) || plan_status=$?
  expect_eq 1 "$plan_status" "Docker $current_docker with runc '${current_runc:-unknown}' stops as already current"
  expect_contains "$plan_output" 'already on target versions' \
    "Docker $current_docker with runc '${current_runc:-unknown}' is not reinstalled"
  expect_not_contains "$plan_output" 'refresh runc' \
    "Docker $current_docker with runc '${current_runc:-unknown}' does not announce a runc refresh"
done
