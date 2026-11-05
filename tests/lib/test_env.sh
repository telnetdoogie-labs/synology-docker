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

assert_eq() {
  [[ "$1" == "$2" ]] || { printf 'FAIL: %s (expected %q, got %q)\n' "$3" "$1" "$2" >&2; return 1; }
}
assert_contains() {
  [[ "$1" == *"$2"* ]] || { printf 'FAIL: %s (missing %q)\n' "$3" "$2" >&2; return 1; }
}
assert_not_contains() {
  [[ "$1" != *"$2"* ]] || { printf 'FAIL: %s (unexpected %q)\n' "$3" "$2" >&2; return 1; }
}
