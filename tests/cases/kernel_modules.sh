#!/bin/bash
# Kernel-module downloads and startup script detection. Run alone with: bash tests/run.sh kernel_modules
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture

# Arrange: fake HTTPS downloads into the isolated module folder.
curl_args_file="$test_tmp_dir/curl-args"

# shellcheck source=install_iptables_modules.sh
source "$repo_dir/install_iptables_modules.sh"
USE_SYSTEMD='false'
KERNEL_VERSION='4.4.302+'
PLATFORM_VERSION=apollolake
MODULES_FOLDER="$test_tmp_dir/modules"
mkdir -p "$MODULES_FOLDER"
IP4MODULE=iptable_raw.ko
IP6MODULE=ip6table_raw.ko
IP4DL='https://example.invalid/ip4'
IP6DL='https://example.invalid/ip6'
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

# Act/expect: download both modules with HTTPS/TLS requirements.
download_and_place_modules >/dev/null
curl_args=$(<"$curl_args_file")
expect_contains "$curl_args" '--proto =https' 'module download requires HTTPS'
expect_contains "$curl_args" '--proto-redir =https' 'redirects require HTTPS'
expect_contains "$curl_args" '--tlsv1.2' 'module download requires TLS 1.2'
expect_file_exists "$MODULES_FOLDER/$IP4MODULE" 'IPv4 module downloaded'
expect_file_exists "$MODULES_FOLDER/$IP6MODULE" 'IPv6 module downloaded'

# Act/expect: a failed download aborts.
# shellcheck disable=SC2329 # Called indirectly by download_and_place_modules via expect_failure.
curl() {
  return 1
}
expect_failure 'failed module download is rejected' download_and_place_modules
unset -f curl

# Arrange/expect: the startup script must load both modules.
FILE="$test_tmp_dir/module-start.sh"
printf '# Load raw modules\n' > "$FILE"
if start_script_loads_modules >/dev/null; then
  printf 'Startup module check passed before modules were configured\n' >&2
  exit 1
fi
printf 'insmod %s/%s\n' "$MODULES_FOLDER" "$IP4MODULE" >> "$FILE"
if start_script_loads_modules >/dev/null; then
  printf 'Startup module check passed with only one module configured\n' >&2
  exit 1
fi
printf 'insmod %s/%s\n' "$MODULES_FOLDER" "$IP6MODULE" >> "$FILE"
expect_success 'startup script loads both modules' start_script_loads_modules >/dev/null
printf 'Module download and startup checks passed\n'
