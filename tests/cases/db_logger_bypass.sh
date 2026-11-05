#!/bin/bash
# Forced/staged/skipped updates bypass preflight; inspection failure blocks. Run alone with: bash tests/run.sh db_logger_bypass
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture

# Arrange: Docker has both db and local logger containers.
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

# Act/expect: force skips the preflight entirely.
force='true'
db_forced_output=$(validate_db_logger 2>&1)
expect_eq '' "$db_forced_output" 'force bypasses DB preflight without output'

# Act/expect: inspection failure still blocks an unforced update.
force='false'
# shellcheck disable=SC2329 # Called indirectly by validate_db_logger via expect_failure.
docker() {
  if [[ "$1" = 'ps' && "${2:-}" = '-aq' ]]; then
    printf 'container-one\n'
    return 0
  fi
  return 1
}
expect_failure 'failed inspection blocks unforced update' validate_db_logger

# Act/expect: skipped and staged updates bypass inspection.
skip_docker_update='true'
docker() { return 1; }
validate_db_logger
stage='true'
skip_docker_update='false'
validate_db_logger
stage='false'
docker() { [[ "$1" = ps ]]; }
printf "DB-logger bypass and failure paths passed\n"
