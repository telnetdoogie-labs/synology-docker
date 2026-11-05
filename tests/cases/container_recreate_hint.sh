#!/bin/bash
# The best-effort hint includes inline env, local logger, and a copyable command.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: use the shared fake Docker inventory and inspected container.
# shellcheck source=tests/lib/container_fixture.sh
source "$(dirname "$0")/../lib/container_fixture.sh"

# Act: render a best-effort command from the inspected container.
suggestion=$("$repo_dir/container_recreate.sh" review-test)

# Expect: inline env, bindings, mounts, logger, and image are represented.
expect_contains "$suggestion" 'docker run -d' 'renders a detached docker run'
expect_contains "$suggestion" '--name review-test' 'retains container name'
expect_contains "$suggestion" '-e "RECREATE_TEST_APP=one"' 'renders first inline environment value'
expect_contains "$suggestion" '-e "RECREATE_TEST_APP_EXTRA=two"' 'renders second inline environment value'
expect_contains "$suggestion" '-p 8080:80/tcp' 'retains port binding'
expect_contains "$suggestion" '-v /tmp/source path:/data path' 'retains bind mount with spaces'
expect_contains "$suggestion" '-v /var/lib/docker/volumes/config_volume/_data:/config' 'retains named volume'
expect_contains "$suggestion" '--log-driver local' 'replaces db logger with local'
expect_contains "$suggestion" '-it example/test:1' 'retains interactive mode and image'

# Act/expect: execute the rendered command against the mocked docker function.
run_result=$(eval "$suggestion")
expect_contains "$run_result" MOCK_DOCKER_RUN 'rendered command invokes Docker'
expect_contains "$run_result" '<-e>
<RECREATE_TEST_APP=one>' 'Docker receives inline environment argument'
expect_contains "$run_result" '<--log-driver>
<local>' 'Docker receives local logger argument'
printf 'Container recreation rendering tests passed\n'
