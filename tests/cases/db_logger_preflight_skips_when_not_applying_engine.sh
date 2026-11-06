#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/db_logger_fixture.sh
source "$(dirname "$0")/../lib/db_logger_fixture.sh"

# Arrange: Docker inspection would fail if it were attempted.
prepare_db_logger_fixture
docker() { return 1; }

# Act/expect: skipping the engine or staging must not inspect containers.
skip_docker_update='true'
validate_db_logger
stage='true'
skip_docker_update='false'
validate_db_logger
