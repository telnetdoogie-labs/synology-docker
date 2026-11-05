#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/container_fixture.sh
source "$(dirname "$0")/../lib/container_fixture.sh"

# Arrange: Docker reports an unmanaged container.
MOCK_LIST_MODE=unmanaged
MOCK_DOCKER_IDS=review-list-test
export MOCK_LIST_MODE MOCK_DOCKER_IDS

# Act: list the unmanaged container.
listing=$("$repo_dir/syno_docker_list_containers.sh")

# Expect: a copyable command switches the old db logger to local.
expect_contains "$listing" 'docker run -d' 'unmanaged container gets a recreation command'
expect_contains "$listing" '--log-driver local' 'recreation command uses local logger'
