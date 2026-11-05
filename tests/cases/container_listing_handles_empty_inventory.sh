#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/container_fixture.sh
source "$(dirname "$0")/../lib/container_fixture.sh"

# Arrange: Docker reports no containers.
MOCK_LIST_MODE=empty
MOCK_DOCKER_IDS=''
export MOCK_LIST_MODE MOCK_DOCKER_IDS

# Act: list the empty inventory.
listing=$("$repo_dir/syno_docker_list_containers.sh")

# Expect: a heading, but no spurious recreation hint.
expect_contains "$listing" Container 'empty inventory keeps the listing heading'
expect_not_contains "$listing" 'docker run' 'empty inventory has no recreation command'
