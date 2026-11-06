#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: the simulated HTTPS endpoint fails.
init_update_fixture
curl() { return 22; }
target_docker_version=''
target_compose_version=''

# Act/expect: lookup failure is not reported as an empty release list.
expect_failure 'failed Docker version lookup aborts' detect_available_versions
