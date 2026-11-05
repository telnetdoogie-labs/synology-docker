#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/container_fixture.sh
source "$(dirname "$0")/../lib/container_fixture.sh"

# Arrange: Docker's container-listing command fails.
MOCK_LIST_MODE=ps_fail
export MOCK_LIST_MODE

# Act: try to list containers.
if listing=$("$repo_dir/syno_docker_list_containers.sh" 2>&1); then
  printf 'FAIL: failed Docker inventory was reported as empty\n' >&2
  exit 1
fi

# Expect: an explicit error, not a misleading inventory.
expect_contains "$listing" 'Could not list Docker containers' 'Docker query error is visible'
expect_not_contains "$listing" Compose_Location 'failed query emits no misleading inventory'
