#!/bin/bash
# The updater supports both DSM 6 and 7, including their distinct package tools.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/dsm_runtime_fixture.sh
source "$(dirname "$0")/../lib/dsm_runtime_fixture.sh"

# Arrange: both DSM package tools are present in the disposable image.
prepare_dsm_runtime_fixture
# The updater queries version CLIs before its DSM check; provide coherent stubs.
docker() {
  case "$1" in
    ps) return 0 ;;
    -v) printf 'Docker version 27.0.0, build test\n' ;;
    *) return 1 ;;
  esac
}
docker-compose() { printf 'Docker Compose version v2.42.0\n'; }
containerd() { printf 'containerd github.com/containerd/containerd v1.7.0\n'; }
runc() { printf 'runc version v1.1.0\n'; }
command='restore' # Isolate DSM compatibility from Docker version availability.

for major in 6 7; do
  # Arrange: write the version file read by the updater; do not preselect a tool.
  set_mock_dsm_version "$major" "$major.2"
  dsm_major_version=''
  output_file="$test_tmp_dir/updater-dsm-$major.txt"

  # Act: detect the real version in this shell, then validate its package tool.
  detect_current_versions > "$output_file"
  expect_eq "$major" "$dsm_major_version" "updater retains detected DSM $major for service control"
  validate_syno_tools

  # Expect: both supported versions complete the same updater checks.
  expect_file_contains "$output_file" "Current DSM version: $major.2" "updater detects DSM $major"
done
