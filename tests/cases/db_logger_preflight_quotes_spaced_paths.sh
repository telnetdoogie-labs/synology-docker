#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/db_logger_fixture.sh
source "$(dirname "$0")/../lib/db_logger_fixture.sh"

# Arrange: execute the updater script from a directory with spaces.
prepare_db_logger_fixture
set_daemon_log_driver db
space_dir="$test_tmp_dir/script directory"
mkdir -p "$space_dir"
cp "$repo_dir/syno_docker_update.sh" "$space_dir/syno_docker_update.sh"

# Act: run preflight with a db-logger container under that script path.
if spaced_output=$(bash -c '
  docker() {
    case "${1:-}:${2:-}" in
      ps:-q) return 0 ;;
      ps:-aq) printf "container-one\n" ;;
      inspect:container-one) printf "/container-one db\n" ;;
      *) return 1 ;;
    esac
  }
  source "$1"
  validate_db_logger
' _ "$space_dir/syno_docker_update.sh" 2>&1); then
  printf 'FAIL: db-logger container was not blocked from a spaced script path\n' >&2
  exit 1
fi

# Expect: both suggested commands quote the path exactly.
printf -v logger_hint '  sudo %q logger' "$space_dir/syno_docker_update.sh"
printf -v listing_hint '  sudo %q' "$space_dir/syno_docker_list_containers.sh"
expect_success 'logger hint quotes spaced script path' grep -Fqx -- "$logger_hint" <<< "$spaced_output"
expect_success 'inventory hint quotes spaced script path' grep -Fqx -- "$listing_hint" <<< "$spaced_output"
