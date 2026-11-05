#!/bin/bash
# Empty container inventory does not block the update. Run alone with: bash tests/run.sh db_logger_empty
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: Docker reports no containers.
init_update_fixture

skip_docker_update='false'
stage='false'
docker() { return 0; }

# Act: run the logger preflight.
db_blocked_output=$(validate_db_logger 2>&1)

# Expect: the update is allowed without a warning.
expect_eq '' "$db_blocked_output" 'empty inventory produces no warning'
printf "Empty inventory logger preflight passed\n"
