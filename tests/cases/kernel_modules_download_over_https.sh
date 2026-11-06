#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/kernel_modules_fixture.sh
source "$(dirname "$0")/../lib/kernel_modules_fixture.sh"

# Arrange: fake downloads into the isolated module folder.
prepare_kernel_modules_fixture
curl_args_file="$test_tmp_dir/curl-args"
curl() {
  printf '%s\n' "$*" > "$curl_args_file"
  local url='' destination=''
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -o) destination=$2; shift 2 ;;
      https:*) url=$1; shift ;;
      *) shift ;;
    esac
  done
  if [[ "$url" = "$IP4DL" ]]; then
    printf 'ip4\n' > "$destination"
  else
    printf 'ip6\n' > "$destination"
  fi
}

# Act: download the IPv4 and IPv6 modules.
download_and_place_modules >/dev/null

# Expect: both files exist and TLS constraints were passed to curl.
curl_args=$(<"$curl_args_file")
expect_contains "$curl_args" '--proto =https' 'module download requires HTTPS'
expect_contains "$curl_args" '--proto-redir =https' 'redirects require HTTPS'
expect_contains "$curl_args" '--tlsv1.2' 'module download requires TLS 1.2'
expect_file_exists "$MODULES_FOLDER/$IP4MODULE" 'IPv4 module downloaded'
expect_file_exists "$MODULES_FOLDER/$IP6MODULE" 'IPv6 module downloaded'
