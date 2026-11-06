#!/bin/bash
# Inline environment and command arguments should be safely replayable.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/container_fixture.sh
source "$(dirname "$0")/../lib/container_fixture.sh"
# shellcheck source=tests/lib/recreate_hint_fixture.sh
source "$(dirname "$0")/../lib/recreate_hint_fixture.sh"

# Arrange: the shared inspected container has spaces and shell syntax in Env/Cmd.
# Act: render a hint and execute it only against the fake Docker.
render_recreate_hint
printf -v quoted_env '%q' "$malicious_env"

# Expect: data remains one argument and is never evaluated as a shell command.
expect_contains "$suggestion" 'docker run -d' 'renders a detached command'
expect_contains "$suggestion" '--name review-test' 'retains container name'
expect_contains "$suggestion" "-e $quoted_env" 'quotes inline environment data'
expect_contains "$suggestion" '-e RECREATE_TEST_APP_EXTRA=two' 'retains second environment value'
expect_not_contains "$suggestion" '--env-file' 'keeps the simple inline environment workflow'
expect_not_contains "$suggestion" 'RECREATE_ENV_FILE' 'does not require a generated env file'
expect_contains "$run_result" 'MOCK_DOCKER_RUN' 'rendered command invokes fake Docker'
expect_contains "$run_result" "<$malicious_env>" 'passes hostile environment value as one argument'
expect_contains "$run_result" '<RECREATE_TEST_APP_EXTRA=two>' 'passes second environment value'
expect_contains "$run_result" '<argument with spaces>' 'preserves spaced command argument'
expect_contains "$run_result" '<second-argument>' 'preserves following command argument'
expect_contains "$run_result" "<$malicious_cmd>" 'passes hostile command argument as data'
expect_file_absent "$test_tmp_dir/should-not-run-env" 'environment value did not execute'
expect_file_absent "$test_tmp_dir/should-not-run-cmd" 'command argument did not execute'
