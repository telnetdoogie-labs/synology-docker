#!/bin/bash
# DB-logger containers block update with useful migration hints. Run alone with: bash tests/run.sh db_logger_preflight
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture

# Arrange: one db-logger container, one local-logger container, and a db daemon default.
skip_docker_update='false'
stage='false'
docker() {
  if [[ "$1" = 'ps' && "${2:-}" = '-aq' ]]; then
    printf 'container-one\ncontainer-two\n'
    return 0
  fi
  if [[ "$1" = 'inspect' ]]; then
    case "$2" in
      container-one) printf '/container-one db\n' ;;
      container-two) printf '/container-two local\n' ;;
      *) return 1 ;;
    esac
    return 0
  fi
  return 1
}
# Explicitly test a DB-default daemon, independent of other cases
jq '.["log-driver"] = "db"' "$SYNO_DOCKER_JSON" > "${SYNO_DOCKER_JSON}.tmp" &&
  mv "${SYNO_DOCKER_JSON}.tmp" "$SYNO_DOCKER_JSON"

# Act/expect: refuse the update and explain migration.
if db_blocked_output=$(validate_db_logger 2>&1); then
  printf 'db-logger containers were not blocked\n' >&2
  exit 1
fi
expect_contains "$db_blocked_output" container-one 'DB logger container must be listed'
expect_not_contains "$db_blocked_output" container-two 'local logger container must not be listed'
expect_contains "$db_blocked_output" --force 'preflight must mention explicit override'
expect_contains "$db_blocked_output" syno_docker_list_containers.sh 'preflight must offer inventory command'
expect_contains "$db_blocked_output" 'git clone https://github.com/gundestrup/stateful-docker-migration-flow' 'preflight must link migration workflow'
expect_contains "$db_blocked_output" 'cd stateful-docker-migration-flow && sudo ./sdmf' 'preflight must show migration command'
expect_contains "$db_blocked_output" 'Review the listed containers and recreate them:' 'preflight must explain recovery'
# A 'db' daemon default must be flagged: recreated containers would inherit it
expect_contains "$db_blocked_output" 'syno_docker_update.sh logger' 'DB daemon default must be flagged'

# Arrange: run the same preflight from a script path containing spaces.
space_dir="$test_tmp_dir/script directory"
mkdir -p "$space_dir"
cp "$repo_dir/syno_docker_update.sh" "$space_dir/syno_docker_update.sh"
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
  printf 'db-logger containers were not blocked from a spaced script path\n' >&2
  exit 1
fi
printf -v logger_hint '  sudo %q logger' "$space_dir/syno_docker_update.sh"
printf -v listing_hint '  sudo %q' "$space_dir/syno_docker_list_containers.sh"
expect_success 'logger hint quotes spaced script path' grep -Fqx -- "$logger_hint" <<< "$spaced_output"
expect_success 'inventory hint quotes spaced script path' grep -Fqx -- "$listing_hint" <<< "$spaced_output"

# Act/expect: a local daemon default removes only the daemon-switch hint.
jq '.["log-driver"] = "local"' "$SYNO_DOCKER_JSON" > "${SYNO_DOCKER_JSON}.tmp" &&
  mv "${SYNO_DOCKER_JSON}.tmp" "$SYNO_DOCKER_JSON"
if db_blocked_output=$(validate_db_logger 2>&1); then
  printf 'db-logger containers were not blocked\n' >&2
  exit 1
fi
expect_contains "$db_blocked_output" container-one 'DB container still blocked when daemon default is local'
expect_not_contains "$db_blocked_output" 'syno_docker_update.sh logger' 'local daemon default must not suggest logger switch'
expect_contains "$db_blocked_output" 'Review the listed containers and recreate them:' 'local default still needs container recreation'
printf "DB-logger migration guidance passed\n"
