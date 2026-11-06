#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/container_fixture.sh
source "$(dirname "$0")/../lib/container_fixture.sh"

# Arrange: a Compose-managed container has a config path containing spaces.
compose_path="$test_tmp_dir/compose  file.yml"
: > "$compose_path"
MOCK_LIST_MODE=true
MOCK_DOCKER_IDS=review-list-test
export MOCK_LIST_MODE MOCK_DOCKER_IDS COMPOSE_PATH="$compose_path"

# Act: list the Compose-managed container.
listing=$("$repo_dir/syno_docker_list_containers.sh")

# Expect: its exact Compose path survives formatting.
expect_contains "$listing" "$compose_path" 'Compose path survives spaces'
