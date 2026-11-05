#!/bin/bash
# Docker and Compose lookup selects newest versions using HTTPS. Run alone with: bash tests/run.sh remote_versions
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture

# Arrange: use a fake HTTPS version endpoint.
curl_args_file="$test_tmp_dir/curl-args"

# Act/expect: a failed lookup is an error, not an empty version.
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

# Act/expect: numeric ordering selects newest engine and Compose release.
detect_available_versions
expect_eq 100.0.0 "$target_docker_version" 'numeric sort selects latest engine'
expect_eq 2.42.0 "$target_compose_version" 'Compose release tag is parsed'
curl_args=$(<"$curl_args_file")
expect_contains "$curl_args" '--proto =https' 'version lookup requires HTTPS'
expect_contains "$curl_args" '--proto-redir =https' 'version lookup redirects require HTTPS'
expect_contains "$curl_args" '--tlsv1.2' 'version lookup requires TLS 1.2'
unset -f curl
printf "Remote version detection tests passed\n"
