#!/bin/bash
# Staging retains downloads without touching installed files. Run alone with: bash tests/run.sh stage_update
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture
prepare_installed_files

mkdir -p "$test_tmp_dir/engine/docker" /etc.defaults
cp "$SYNO_DOCKER_BIN/docker" "$test_tmp_dir/engine/docker/docker"
cp "$SYNO_DOCKER_BIN/dockerd" "$test_tmp_dir/engine/docker/dockerd"
printf 'staged-only\n' >> "$test_tmp_dir/engine/docker/docker"
installed_docker_hash=$(sha256sum "$SYNO_DOCKER_BIN/docker" | cut -d' ' -f1)
installed_config_hash=$(sha256sum "$SYNO_DOCKER_JSON" | cut -d' ' -f1)
installed_script_hash=$(sha256sum "$SYNO_DOCKER_SCRIPT" | cut -d' ' -f1)
tar -czf "$test_tmp_dir/engine.tgz" -C "$test_tmp_dir/engine" docker
printf 'compose-binary\n' > "$test_tmp_dir/compose-binary"
printf 'majorversion="7"\nproductversion="7.2"\n' > /etc.defaults/VERSION
stage_output=$(
  docker() {
    case "$1" in
      ps) return 0 ;;
      -v) printf 'Docker version 28.0.0, build test\n' ;;
      *) return 1 ;;
    esac
  }
  docker-compose() { printf 'Docker Compose version v2.1.1\n'; }
  containerd() { printf 'containerd containerd.io v1.7.0\n'; }
  runc() { printf 'runc version 1.1.0\n'; }
  curl() {
    local url='' destination=''
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        -o) destination=$2; shift 2 ;;
        https:*) url=$1; shift ;;
        *) shift ;;
      esac
    done
    case "$url" in
      "$DOWNLOAD_DOCKER/docker-29.0.0.tgz") cp "$test_tmp_dir/engine.tgz" "$destination" ;;
      */docker-compose-linux-x86_64) cp "$test_tmp_dir/compose-binary" "$destination" ;;
      *) return 22 ;;
    esac
    printf 200
  }
  download_dir=''
  temp_dir=''
  service_stopped='false'
  main --force --stage --path "$test_tmp_dir" --backup staged.tgz --docker 29.0.0 --compose 2.42.0 --target all update
)
stage_dir=$(printf '%s\n' "$stage_output" | sed -n 's/^Staged files: //p' | tail -n 1)
[[ -n "$stage_dir" && -f "$stage_dir/docker-29.0.0.tgz" && -f "$stage_dir/docker-compose" ]] || { printf 'FAIL: stage must retain both downloads\n' >&2; exit 1; }
[[ -f "$stage_dir/docker/docker" && -f "$test_tmp_dir/staged.tgz" ]] || { printf 'FAIL: stage must retain extracted binary and backup\n' >&2; exit 1; }
assert_eq "$installed_docker_hash" "$(sha256sum "$SYNO_DOCKER_BIN/docker" | cut -d' ' -f1)" 'stage must not replace installed Docker'
assert_eq "$installed_config_hash" "$(sha256sum "$SYNO_DOCKER_JSON" | cut -d' ' -f1)" 'stage must not alter daemon config'
assert_eq "$installed_script_hash" "$(sha256sum "$SYNO_DOCKER_SCRIPT" | cut -d' ' -f1)" 'stage must not alter service script'
rm -rf "$stage_dir"
printf 'Stage workflow retains its downloads without changing the installed binaries\n'
