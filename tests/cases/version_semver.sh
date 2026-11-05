#!/bin/bash
# Semantic-version ordering and invalid-version rejection. Run alone with: bash tests/run.sh version_semver
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture

version_is_newer 100.0.0 29.9.9
version_is_newer 29.10.0 29.9.9
if version_is_newer 29.9.9 29.10.0 || version_is_newer 29.0.0 29.0.0; then
  printf 'Version comparison unexpectedly accepted a downgrade/equal version\n' >&2
  exit 1
fi
is_semver 29.1.0
if is_semver 29.1; then
  printf 'Invalid semver unexpectedly accepted\n' >&2
  exit 1
fi
printf "Version comparison tests passed\n"
