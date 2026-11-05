#!/bin/bash
# Forced/staged/skipped updates bypass preflight; inspection failure blocks. Run alone with: bash tests/run.sh db_logger_bypass
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture

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
jq '.["log-driver"] = "db"' "$SYNO_DOCKER_JSON" > "${SYNO_DOCKER_JSON}.tmp" &&
  mv "${SYNO_DOCKER_JSON}.tmp" "$SYNO_DOCKER_JSON"
force='true'
db_forced_output=$(validate_db_logger 2>&1)
[[ -z "$db_forced_output" ]]
force='false'
docker() {
  if [[ "$1" = 'ps' && "${2:-}" = '-aq' ]]; then
    printf 'container-one\n'
    return 0
  fi
  return 1
}
if (validate_db_logger) >/dev/null 2>&1; then
  printf 'db-logger inspection failure was not blocked\n' >&2
  exit 1
fi
skip_docker_update='true'
docker() { return 1; }
validate_db_logger
stage='true'
skip_docker_update='false'
validate_db_logger
stage='false'
docker() { [[ "$1" = ps ]]; }
printf "DB-logger bypass and failure paths passed\n"
