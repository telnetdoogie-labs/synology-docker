#!/bin/bash
# Backup extraction, restore, and failed-copy handling. Run alone with: bash tests/run.sh restore
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture
prepare_installed_files
docker_backup_filename=complete.tgz
execute_backup >/dev/null

docker_backup_filename='complete.tgz'
skip_docker_update='false'
skip_compose_update='false'
skip_driver_update='false'
stage='false'
temp_dir=$(mktemp -d)
execute_extract_backup >/dev/null
printf 'changed binary\n' > "$SYNO_DOCKER_BIN/docker"
execute_restore_bin >/dev/null
execute_restore_log >/dev/null
execute_restore_script >/dev/null
cmp -s "$temp_dir/docker/docker" "$SYNO_DOCKER_BIN/docker"
cmp -s "$temp_dir/dockerd.json" "$SYNO_DOCKER_JSON"
cmp -s "$temp_dir/start-stop-status" "$SYNO_DOCKER_SCRIPT"
cd "$repo_dir"
rm -rf "$temp_dir"
temp_dir=''
printf 'Backup extraction and successful restore tests passed\n'

temp_dir=$(mktemp -d)
mkdir -p "$temp_dir/docker"
cp "$SYNO_DOCKER_BIN/docker" "$temp_dir/docker/docker"
skip_docker_update='false'
skip_compose_update='true'
stage='false'
mv "$SYNO_DOCKER_BIN" "${SYNO_DOCKER_BIN}.saved"
: > "$SYNO_DOCKER_BIN"
if (execute_restore_bin) >/dev/null 2>&1; then
  printf 'Failed restore copy was accepted\n' >&2
  exit 1
fi
rm "$SYNO_DOCKER_BIN"
mv "${SYNO_DOCKER_BIN}.saved" "$SYNO_DOCKER_BIN"
rm -rf "$temp_dir"
temp_dir=''
