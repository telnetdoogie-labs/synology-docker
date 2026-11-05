#!/bin/bash
# Syntax check all production and test shell scripts.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: include production scripts, cases, and their shared fixtures.

# Expect: every script parses; the error identifies the exact file.
for script in "$repo_dir"/*.sh "$repo_dir"/tests/*.sh "$repo_dir"/tests/cases/*.sh "$repo_dir"/tests/lib/*.sh; do
  expect_success "shell syntax: ${script#"$repo_dir/"}" bash -n "$script"
done
printf "Shell syntax tests passed\n"
