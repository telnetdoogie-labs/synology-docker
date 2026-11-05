#!/bin/bash
# Logger changes preserve unrelated JSON and reject invalid input. Run alone with: bash tests/run.sh logger_switch
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: start with a valid config containing unrelated settings.
init_update_fixture

logger_json="$test_tmp_dir/dockerd-switch.json"
cp "$repo_dir/test_file/dockerd.json" "$logger_json"

# Act: switch the logger.
sh "$repo_dir/syno_docker_switch_logger.sh" "$logger_json" >/dev/null

# Expect: local logging defaults, with other settings preserved.
expect_eq local "$(jq -r '.["log-driver"]' "$logger_json")" 'switches to local logger'
expect_eq 5 "$(jq -r '.["log-opts"]["max-file"]' "$logger_json")" 'sets max-file'
expect_eq 20m "$(jq -r '.["log-opts"]["max-size"]' "$logger_json")" 'sets max-size'
expect_eq btrfs "$(jq -r '.["storage-driver"]' "$logger_json")" 'preserves storage driver'
expect_eq /usr/bin/nvidia-container-runtime "$(jq -r '.runtimes.nvidia.path' "$logger_json")" 'preserves custom runtime'

# Act/expect: invalid or absent JSON is rejected, without rewriting input.
printf '{invalid\n' > "$logger_json"
expect_failure 'invalid JSON is rejected' sh "$repo_dir/syno_docker_switch_logger.sh" "$logger_json"
expect_eq '{invalid' "$(<"$logger_json")" 'invalid input is left untouched'
expect_failure 'missing JSON is rejected' sh "$repo_dir/syno_docker_switch_logger.sh" "$test_tmp_dir/missing.json"
printf 'Logger switch tests passed\n'
