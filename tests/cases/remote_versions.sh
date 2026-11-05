#!/bin/bash
# Docker and Compose lookup selects newest versions using HTTPS. Run alone with: bash tests/run.sh remote_versions
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture

curl_args_file="$test_tmp_dir/curl-args"
if (curl() { return 22; }; target_docker_version=''; target_compose_version=''; detect_available_versions) >/dev/null 2>&1; then
  printf 'Docker lookup failure unexpectedly succeeded\n' >&2
  exit 1
fi
curl() {
  printf '%s\n' "$*" > "$curl_args_file"
  case "$2" in
    "${DOWNLOAD_DOCKER}/") printf '>docker-9.9.9.tgz\n>docker-29.9.9.tgz\n>docker-100.0.0.tgz\n' ;;
    "$GITHUB_API_COMPOSE") printf '{"tag_name":"v2.42.0"}\n' ;;
    *) return 22 ;;
  esac
}
target_docker_version=''
target_compose_version=''
detect_available_versions
[[ "$target_docker_version" == '100.0.0' ]]
[[ "$target_compose_version" == '2.42.0' ]]
curl_args=$(<"$curl_args_file")
[[ "$curl_args" == *"--proto =https"* ]]
[[ "$curl_args" == *"--proto-redir =https"* ]]
[[ "$curl_args" == *"--tlsv1.2"* ]]
unset -f curl
printf "Remote version detection tests passed\n"
