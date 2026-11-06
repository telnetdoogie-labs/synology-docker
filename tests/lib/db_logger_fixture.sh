#!/bin/bash
# Shared db/local-logger inventory for isolated preflight behavior cases.
# Source after test_env.sh; each case gets a separate disposable shell.
# The updater consumes these globals when this fixture is sourced by a case.
# shellcheck disable=SC2154,SC2034

prepare_db_logger_fixture() {
  init_update_fixture
  skip_docker_update='false'
  stage='false'
  force='false'
}

mock_mixed_logger_containers() {
  # shellcheck disable=SC2329 # Called indirectly by validate_db_logger.
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
}

set_daemon_log_driver() {
  jq --arg driver "$1" '.["log-driver"] = $driver' "$SYNO_DOCKER_JSON" > "${SYNO_DOCKER_JSON}.tmp"
  mv "${SYNO_DOCKER_JSON}.tmp" "$SYNO_DOCKER_JSON"
}
