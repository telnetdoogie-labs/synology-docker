#!/bin/bash
# Compose location, unmanaged hints, empty inventory, and inventory failures.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: use the shared fake Docker inventory and inspected container.
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
expect_contains "$listing" "$compose_path" "Compose path survives spaces"

# Act/expect: unmanaged containers get a local-logger recreation hint.
MOCK_LIST_MODE=unmanaged
export MOCK_LIST_MODE
listing=$("$repo_dir/syno_docker_list_containers.sh")
expect_contains "$listing" 'docker run -d' 'unmanaged container gets a recreation command'
expect_contains "$listing" '--log-driver local' 'recreation command uses local logger'

# Act/expect: an empty inventory is not mistaken for a recreation hint.
MOCK_LIST_MODE=empty
MOCK_DOCKER_IDS=''
export MOCK_LIST_MODE MOCK_DOCKER_IDS
listing=$("$repo_dir/syno_docker_list_containers.sh")
expect_contains "$listing" Container 'empty inventory keeps the listing heading'
expect_not_contains "$listing" 'docker run' 'empty inventory has no recreation command'

# Act/expect: a failed Docker query must not masquerade as empty.
MOCK_LIST_MODE=ps_fail
export MOCK_LIST_MODE
if listing=$("$repo_dir/syno_docker_list_containers.sh" 2>&1); then
  printf 'Failed Docker inventory was reported as empty\n' >&2
  exit 1
fi
expect_contains "$listing" 'Could not list Docker containers' 'Docker query error is visible'
expect_not_contains "$listing" Compose_Location 'failed query emits no misleading inventory'
printf 'Container listing path tests passed\n'
