#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/db_logger_fixture.sh
source "$(dirname "$0")/../lib/db_logger_fixture.sh"

# Arrange: a db-logger container, a local-logger container, and a db daemon default.
prepare_db_logger_fixture
mock_mixed_logger_containers
set_daemon_log_driver db

# Act: run the preflight; a db-logger container must block the update.
if blocked_output=$(validate_db_logger 2>&1); then
  printf 'FAIL: db-logger container did not block update\n' >&2
  exit 1
fi

# Expect: only affected containers are listed with actionable recovery hints.
expect_contains "$blocked_output" container-one 'DB logger container must be listed'
expect_not_contains "$blocked_output" container-two 'local logger container must not be listed'
expect_contains "$blocked_output" --force 'preflight must mention explicit override'
expect_contains "$blocked_output" syno_docker_list_containers.sh 'preflight must offer inventory command'
expect_contains "$blocked_output" 'git clone https://github.com/gundestrup/stateful-docker-migration-flow' 'preflight must link migration workflow'
expect_contains "$blocked_output" 'cd stateful-docker-migration-flow && sudo ./sdmf' 'preflight must show migration command'
expect_contains "$blocked_output" 'Review the listed containers and recreate them:' 'preflight must explain recovery'
expect_contains "$blocked_output" 'syno_docker_update.sh logger' 'db daemon default must be switched before recreation'
