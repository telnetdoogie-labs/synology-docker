#!/bin/bash
# Syntax check all production and test shell scripts.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
for script in "$repo_dir"/*.sh "$repo_dir"/tests/*.sh "$repo_dir"/tests/cases/*.sh "$repo_dir"/tests/lib/*.sh; do
  bash -n "$script"
done
printf "Shell syntax tests passed\n"
