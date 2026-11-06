#!/bin/bash
# The basic recreate hint remains useful for non-Compose containers.
# It is best-effort, not a guarantee of a complete container reconstruction.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/container_fixture.sh
source "$(dirname "$0")/../lib/container_fixture.sh"

# Arrange: shared Docker inspection fixture uses a db logger and TTY.
# Act: render the basic recreation suggestion.
suggestion=$("$repo_dir/container_recreate.sh" review-test)

# Expect: the command names the container, replaces db logging, retains image/TTY.
expect_contains "$suggestion" 'docker run -d' 'renders a detached Docker command'
expect_contains "$suggestion" '--name review-test' 'retains container name'
expect_contains "$suggestion" '--log-driver local' 'replaces db logger with local'
expect_contains "$suggestion" '-it example/test:1' 'retains image and TTY'
