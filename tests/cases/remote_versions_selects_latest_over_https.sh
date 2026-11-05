#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: version endpoints list engines whose numeric and lexical order differ.
init_update_fixture
curl_args_file="$test_tmp_dir/curl-args"
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

# Act: look up the newest engine and Compose release.
detect_available_versions

# Expect: numeric engine ordering and HTTPS-only downloads.
expect_eq 100.0.0 "$target_docker_version" 'numeric sort selects latest engine'
expect_eq 2.42.0 "$target_compose_version" 'Compose release tag is parsed'
curl_args=$(<"$curl_args_file")
expect_contains "$curl_args" '--proto =https' 'version lookup requires HTTPS'
expect_contains "$curl_args" '--proto-redir =https' 'version lookup redirects require HTTPS'
expect_contains "$curl_args" '--tlsv1.2' 'version lookup requires TLS 1.2'
