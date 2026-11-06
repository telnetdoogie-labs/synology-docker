#!/bin/bash
# Semantic-version ordering and invalid-version rejection. Run alone with: bash tests/run.sh version_semver
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: compare versions across major and minor boundaries.
init_update_fixture

# Expect: numeric version ordering, not lexicographic sorting.
expect_success '100 is newer than 29' version_is_newer 100.0.0 29.9.9
expect_success '29.10 is newer than 29.9' version_is_newer 29.10.0 29.9.9
expect_failure 'older version is not newer' version_is_newer 29.9.9 29.10.0
expect_failure 'equal version is not newer' version_is_newer 29.0.0 29.0.0

# Expect: exactly three numeric components in a semantic version.
expect_success 'three components form a semver' is_semver 29.1.0
expect_failure 'two components are invalid' is_semver 29.1
printf "Version comparison tests passed\n"
