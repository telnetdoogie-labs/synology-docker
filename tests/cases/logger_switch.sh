#!/bin/bash
# Logger changes preserve unrelated JSON and reject invalid input. Run alone with: bash tests/run.sh logger_switch
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture

logger_json="$test_tmp_dir/dockerd-switch.json"
cp "$repo_dir/test_file/dockerd.json" "$logger_json"
sh "$repo_dir/syno_docker_switch_logger.sh" "$logger_json" >/dev/null
[[ "$(jq -r '.["log-driver"]' "$logger_json")" == 'local' ]]
[[ "$(jq -r '.["log-opts"]["max-file"]' "$logger_json")" == '5' ]]
[[ "$(jq -r '.["log-opts"]["max-size"]' "$logger_json")" == '20m' ]]
[[ "$(jq -r '.["storage-driver"]' "$logger_json")" == 'btrfs' ]]
[[ "$(jq -r '.runtimes.nvidia.path' "$logger_json")" == '/usr/bin/nvidia-container-runtime' ]]
printf '{invalid\n' > "$logger_json"
if (sh "$repo_dir/syno_docker_switch_logger.sh" "$logger_json") >/dev/null 2>&1; then
  printf 'Invalid dockerd.json was accepted\n' >&2
  exit 1
fi
[[ "$(cat "$logger_json")" == '{invalid' ]]
if (sh "$repo_dir/syno_docker_switch_logger.sh" "$test_tmp_dir/missing.json") >/dev/null 2>&1; then
  printf 'Missing dockerd.json was accepted\n' >&2
  exit 1
fi
printf 'Logger switch tests passed\n'
