#!/bin/bash
# Every case sources this fixture. All DSM writes happen inside the disposable test image.
set -euo pipefail
if [[ "${DSM_MOCK_CONTAINER:-}" != 1 || "$(id -u)" -ne 0 || ! -f /etc/synology-docker-test-image ]]; then
  printf 'Run tests only as root inside the disposable Docker test image\n' >&2
  exit 1
fi
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
test_tmp_dir=$(mktemp -d)
trap 'rm -rf "$test_tmp_dir"' EXIT
trap 'printf "FAIL: %s at line %s: %s\n" "${BASH_SOURCE[0]}" "$LINENO" "$BASH_COMMAND" >&2' ERR

init_update_fixture() {
  # A new shell per case isolates function mocks and globals; reset simulated DSM files.
  rm -rf /var/packages/ContainerManager
  mkdir -p /var/packages/ContainerManager/{target/usr/bin,etc,scripts} /usr/syno/{bin,sbin}
  docker() { [[ "$1" = ps ]]; }
  # shellcheck source=syno_docker_update.sh
  source "$repo_dir/syno_docker_update.sh"
  cp "$repo_dir/test_file/dockerd.json" "$SYNO_DOCKER_JSON"
}

prepare_installed_files() {
  for binary in docker dockerd docker-compose; do
    printf '#!/bin/sh\n' > "$SYNO_DOCKER_BIN/$binary"
  done
  cp "$repo_dir/test_file/dockerd.json" "$SYNO_DOCKER_JSON"
  cp "$repo_dir/test_file/start-stop-status" "$SYNO_DOCKER_SCRIPT"
  backup_dir="$test_tmp_dir"
}

# Expected value first, observed value second. Every failure names the contract.
expect_eq() {
  [[ "$1" == "$2" ]] || { printf 'FAIL: %s (expected %q, got %q)\n' "$3" "$1" "$2" >&2; return 1; }
}
expect_contains() {
  [[ "$1" == *"$2"* ]] || { printf 'FAIL: %s (missing %q)\n' "$3" "$2" >&2; return 1; }
}
expect_not_contains() {
  [[ "$1" != *"$2"* ]] || { printf 'FAIL: %s (unexpected %q)\n' "$3" "$2" >&2; return 1; }
}
expect_success() {
  local description=$1
  shift
  "$@" || { printf 'FAIL: %s (command failed: %s)\n' "$description" "$*" >&2; return 1; }
}
expect_failure() {
  local description=$1
  shift
  # A failure path may call exit; contain it so the assertion can report the result.
  if ("$@") >/dev/null 2>&1; then
    printf 'FAIL: %s (command unexpectedly succeeded: %s)\n' "$description" "$*" >&2
    return 1
  fi
}
expect_file_exists() {
  [[ -f "$1" ]] || { printf 'FAIL: %s (missing file: %s)\n' "$2" "$1" >&2; return 1; }
}
expect_file_absent() {
  [[ ! -e "$1" ]] || { printf 'FAIL: %s (unexpected file: %s)\n' "$2" "$1" >&2; return 1; }
}
expect_files_equal() {
  cmp -s "$1" "$2" || { printf 'FAIL: %s (files differ: %s and %s)\n' "$3" "$1" "$2" >&2; return 1; }
}
expect_file_contains() {
  grep -Fq -- "$2" "$1" || { printf 'FAIL: %s (file %s lacks %q)\n' "$3" "$1" "$2" >&2; return 1; }
}
expect_file_lacks() {
  local file=$1 needle=$2 description=$3
  [[ -r "$file" ]] || { printf 'FAIL: %s (unreadable file: %s)\n' "$description" "$file" >&2; return 1; }
  if grep -Fq -- "$needle" "$file"; then
    printf 'FAIL: %s (file %s contains %q)\n' "$description" "$file" "$needle" >&2
    return 1
  fi
}
expect_file_occurrences() {
  local file=$1 needle=$2 expected=$3 description=$4 observed
  observed=$(awk -v needle="$needle" 'index($0, needle) { n++ } END { print n+0 }' "$file") || return 1
  expect_eq "$expected" "$observed" "$description"
}
