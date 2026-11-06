#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: the destination for engine binaries is a file, not a directory.
init_update_fixture
prepare_installed_files
temp_dir=$(mktemp -d)
mkdir -p "$temp_dir/docker"
cp "$SYNO_DOCKER_BIN/docker" "$temp_dir/docker/docker"
skip_docker_update='false'
skip_compose_update='true'
stage='false'
mv "$SYNO_DOCKER_BIN" "${SYNO_DOCKER_BIN}.saved"
: > "$SYNO_DOCKER_BIN"

# Act/expect: a failed copy cannot be reported as a successful restore.
expect_failure 'failed copy aborts restore' execute_restore_bin

# Restore only the disposable test fixture for clean teardown.
rm "$SYNO_DOCKER_BIN"
mv "${SYNO_DOCKER_BIN}.saved" "$SYNO_DOCKER_BIN"
rm -rf "$temp_dir"
temp_dir=''
