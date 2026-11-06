#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/db_logger_fixture.sh
source "$(dirname "$0")/../lib/db_logger_fixture.sh"

# Arrange: the daemon default is already local, but a container still uses db.
prepare_db_logger_fixture
mock_mixed_logger_containers
set_daemon_log_driver local

# Act: run the preflight.
if blocked_output=$(validate_db_logger 2>&1); then
  printf 'FAIL: db-logger container was not blocked with local daemon default\n' >&2
  exit 1
fi

# Expect: recreation guidance remains, without a redundant daemon switch.
expect_contains "$blocked_output" container-one 'DB container still blocked when daemon default is local'
expect_not_contains "$blocked_output" 'syno_docker_update.sh logger' 'local daemon default must not suggest logger switch'
expect_contains "$blocked_output" 'Review the listed containers and recreate them:' 'local default still needs container recreation'
