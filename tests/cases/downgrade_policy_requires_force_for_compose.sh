#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: installed Compose is newer than the requested version.
init_update_fixture
force='false'
skip_docker_update='true'
skip_compose_update='false'
compose_version='2.42.0'
target_compose_version='2.1.1'

# Act/expect: an unforced Compose downgrade is rejected.
expect_failure 'Compose downgrade needs explicit force' define_update
