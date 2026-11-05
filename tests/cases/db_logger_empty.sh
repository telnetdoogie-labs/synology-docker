#!/bin/bash
# Empty container inventory does not block the update. Run alone with: bash tests/run.sh db_logger_empty
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture

skip_docker_update='false'
stage='false'
docker() { return 0; }
db_blocked_output=$(validate_db_logger 2>&1)
[[ -z "$db_blocked_output" ]]
printf "Empty inventory logger preflight passed\n"
