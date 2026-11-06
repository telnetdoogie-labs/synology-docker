#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/db_logger_fixture.sh
source "$(dirname "$0")/../lib/db_logger_fixture.sh"

# Arrange: the daemon defaults to db and an affected container exists.
prepare_db_logger_fixture
mock_mixed_logger_containers
set_daemon_log_driver db
force='true'

# Act: run the preflight with force.
forced_output=$(validate_db_logger 2>&1)

# Expect: explicit force bypasses the warning.
expect_eq '' "$forced_output" 'force bypasses DB preflight without output'
