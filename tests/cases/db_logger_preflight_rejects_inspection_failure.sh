#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/db_logger_fixture.sh
source "$(dirname "$0")/../lib/db_logger_fixture.sh"

# Arrange: Docker lists a container but inspection fails.
prepare_db_logger_fixture
# shellcheck disable=SC2329 # Called indirectly by validate_db_logger.
docker() {
  if [[ "$1" = 'ps' && "${2:-}" = '-aq' ]]; then
    printf 'container-one\n'
    return 0
  fi
  return 1
}

# Act/expect: uncertain logger state blocks an unforced update.
expect_failure 'failed inspection blocks unforced update' validate_db_logger
