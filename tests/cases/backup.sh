#!/bin/bash
# Backup permissions and incomplete backup rejection. Run alone with: bash tests/run.sh backup
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture
prepare_installed_files

docker_backup_filename='complete.tgz'
execute_backup >/dev/null
[[ -s "$backup_dir/$docker_backup_filename" ]] || { printf 'FAIL: backup archive must be non-empty\n' >&2; exit 1; }
assert_eq 600 "$(stat -c %a "$backup_dir/$docker_backup_filename")" 'backup archive must be owner-only'
if (execute_backup) >/dev/null 2>&1; then
  printf 'Backup was overwritten\n' >&2
  exit 1
fi
rm "$SYNO_DOCKER_JSON"
docker_backup_filename='incomplete.tgz'
if (execute_backup) >/dev/null 2>&1; then
  printf 'Incomplete backup was accepted\n' >&2
  exit 1
fi
[[ ! -e "$backup_dir/$docker_backup_filename" ]] || { printf 'FAIL: incomplete backup must not leave an archive\n' >&2; exit 1; }
printf 'Backup validation tests passed\n'
