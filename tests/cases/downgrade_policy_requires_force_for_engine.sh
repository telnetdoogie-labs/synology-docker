#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: installed engine is newer than the requested explicit target.
init_update_fixture
force='false'
docker_version='29.0.0'
target_docker_version='28.0.0'
skip_docker_update='false'
skip_compose_update='true'
skip_driver_update='true'

# Act/expect: an unforced downgrade is rejected.
expect_failure 'engine downgrade needs explicit force' define_update

# Act/expect: explicit target plus force permits the downgrade.
force='true'
target_docker_explicit='true'
define_update
