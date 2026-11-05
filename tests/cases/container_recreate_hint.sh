#!/bin/bash
# The best-effort hint displays inline env, mounts, logger, and image.
# It does NOT prove that the suggested command faithfully recreates a container.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: use the shared fake Docker inventory and inspected container.
# shellcheck source=tests/lib/container_fixture.sh
source "$(dirname "$0")/../lib/container_fixture.sh"

# Act: render a best-effort command from the inspected container.
suggestion=$("$repo_dir/container_recreate.sh" review-test)

# Expect: the hint displays selected values (not shell-safe argv for every value).
expect_contains "$suggestion" 'docker run -d' 'renders a detached docker run'
expect_contains "$suggestion" '--name review-test' 'retains container name'
expect_contains "$suggestion" '-e "RECREATE_TEST_APP=one"' 'renders first inline environment value'
expect_contains "$suggestion" '-e "RECREATE_TEST_APP_EXTRA=two"' 'renders second inline environment value'
expect_contains "$suggestion" '-p 8080:80/tcp' 'displays port numbers (not bind IP)'
expect_contains "$suggestion" '-v /tmp/source path:/data path' 'displays bind mount paths (not argv-safe yet)'
expect_contains "$suggestion" '-v /var/lib/docker/volumes/config_volume/_data:/config' 'retains named volume'
expect_contains "$suggestion" '--log-driver local' 'replaces db logger with local'
expect_contains "$suggestion" 'example/test:1' 'displays image'

# Act/expect: execute against the mock to check *only* the tested env/logger args.
# Do not interpret this as proof that spaced mounts or Cmd argv round-trip.
run_result=$(eval "$suggestion")
expect_contains "$run_result" MOCK_DOCKER_RUN 'rendered command invokes Docker'
expect_contains "$run_result" '<-e>
<RECREATE_TEST_APP=one>' 'Docker receives inline environment argument'
expect_contains "$run_result" '<--log-driver>
<local>' 'Docker receives local logger argument'
printf 'Container recreation rendering tests passed\n'
