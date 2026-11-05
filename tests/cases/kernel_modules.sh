#!/bin/bash
# Kernel-module downloads and startup script detection. Run alone with: bash tests/run.sh kernel_modules
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture
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
download_and_place_modules >/dev/null
curl_args=$(<"$curl_args_file")
[[ "$curl_args" == *"--proto =https"* ]]
[[ "$curl_args" == *"--proto-redir =https"* ]]
[[ "$curl_args" == *"--tlsv1.2"* ]]
[[ -f "$MODULES_FOLDER/$IP4MODULE" && -f "$MODULES_FOLDER/$IP6MODULE" ]]
curl() {
  return 1
}
if (download_and_place_modules) >/dev/null 2>&1; then
  printf 'Failed kernel module download was accepted\n' >&2
  exit 1
fi
unset -f curl
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
start_script_loads_modules >/dev/null
printf 'Module download and startup checks passed\n'
