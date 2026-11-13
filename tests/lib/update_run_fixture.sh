#!/bin/bash
# Mocked DSM 7 externals for cases that drive syno_docker_update.sh through main.
# Source after test_env.sh; call prepare_update_run_fixture after init_update_fixture.
# repo_dir, test_tmp_dir, and the updater constants are intentionally inherited.
# shellcheck disable=SC2154,SC2329 # Mocks are called by the updater, not by this file.

prepare_update_run_fixture() {
  mkdir -p /etc.defaults
  printf 'majorversion="7"\nproductversion="7.2"\n' > /etc.defaults/VERSION
  mock_downloads="$test_tmp_dir/downloads"
  curl_log="$test_tmp_dir/curl.log"
  mkdir -p "$mock_downloads"
  : > "$curl_log"
  # Defined here, not at source time, so they replace the docker stub from init_update_fixture.
  docker() {
    case "$1" in
      ps) return 0 ;;
      -v) [[ -n "$mock_docker_version" ]] && printf 'Docker version %s, build test\n' "$mock_docker_version" ;;
      *) return 1 ;;
    esac
  }
  docker-compose() {
    [[ -n "$mock_compose_version" ]] && printf 'Docker Compose version v%s\n' "$mock_compose_version"
  }
  containerd() { printf 'containerd containerd.io v1.7.0 test\n'; }
  runc() {
    [[ -n "$mock_runc_version" ]] && printf 'runc version %s\ncommit: v%s-0-gtest\n' "$mock_runc_version" "$mock_runc_version"
  }
  mock_installed_versions '' '' ''
  mock_dockerd_running false
}

# DSM 7 package tool that keeps its state between calls and records every action.
#   $1 - status before the run; $2 - status a 'stop' leaves behind (defaults to 'stopped').
mock_synopkg() {
  synopkg_state="$test_tmp_dir/synopkg-state"
  synopkg_log="$test_tmp_dir/synopkg.log"
  printf '%s\n' "$1" > "$synopkg_state"
  : > "$synopkg_log"
  cat > /usr/syno/bin/synopkg <<EOF
#!/bin/sh
printf '%s\n' "\$1" >> "$synopkg_log"
case "\$1" in
  status) cat "$synopkg_state" ;;
  stop) echo "${2:-stopped}" > "$synopkg_state" ;;
  start) echo started > "$synopkg_state" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x /usr/syno/bin/synopkg
}

# Installed Docker, Compose, and runc versions; an empty value means the CLI is unavailable.
mock_installed_versions() {
  mock_docker_version=$1
  mock_compose_version=$2
  mock_runc_version=$3
}

mock_dockerd_running() {
  if [[ "$1" = true ]]; then
    pidof() { [[ "$1" = dockerd ]]; }
  else
    pidof() { return 1; }
  fi
  pgrep() { return 1; }
}

# Serves files from $mock_downloads by URL basename and logs every requested URL.
curl() {
  local url='' destination=''
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -o) destination=$2; shift 2 ;;
      https:*) url=$1; shift ;;
      *) shift ;;
    esac
  done
  printf '%s\n' "$url" >> "$curl_log"
  [[ -f "$mock_downloads/${url##*/}" ]] || return 22
  cp "$mock_downloads/${url##*/}" "$destination"
  printf 200
}

# Publishes docker-VERSION.tgz containing only the named files under docker/.
make_engine_archive() {
  local version=$1 source_dir="$test_tmp_dir/engine-$1" file
  shift
  mkdir -p "$source_dir/docker"
  for file in "$@"; do
    printf '#!/bin/sh\n# new %s\n' "$file" > "$source_dir/docker/$file"
  done
  tar -czf "$mock_downloads/docker-$version.tgz" -C "$source_dir" docker
}

installed_file_hashes() {
  sha256sum "$SYNO_DOCKER_BIN"/* "$SYNO_DOCKER_JSON" "$SYNO_DOCKER_SCRIPT"
}

set_installed_log_driver() {
  local config_temp="$test_tmp_dir/dockerd.json.new"
  jq --arg driver "$1" '.["log-driver"] = $driver' "$SYNO_DOCKER_JSON" > "$config_temp"
  mv "$config_temp" "$SYNO_DOCKER_JSON"
}
