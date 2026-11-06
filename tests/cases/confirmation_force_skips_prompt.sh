#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture

# Arrange: a forced update has no interactive input.
force='true'

# Act: attempt confirmation with stdin closed.
confirm_output=$(confirm_operation </dev/null)

# Expect: no prompt and no failure.
expect_eq '' "$confirm_output" 'forced update does not prompt'
