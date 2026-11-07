#!/bin/bash
# Source after test_env.sh for the isolated kernel-module cases.
# shellcheck disable=SC2154,SC2034

prepare_kernel_modules_fixture() {
  init_update_fixture
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
  SUMSDL='https://example.invalid/SHA256SUMS'
}

# Writes a SHA256SUMS line for module content, using the same relative path as
# synology-kernelmodules (e.g. "4.4.302+/apollolake/iptable_raw.ko").
module_checksum_line() {
  local module=$1 content=$2
  printf '%s  %s/%s/%s\n' "$(printf '%s' "$content" | sha256sum | awk '{ print $1 }')" \
    "$KERNEL_VERSION" "$PLATFORM_VERSION" "$module"
}

# Fakes curl for the two module URLs and SHA256SUMS. Serves $MOCK_IP4_CONTENT and
# $MOCK_IP6_CONTENT as the modules, and $MOCK_SUMS as the checksum file. When
# $MOCK_CURL_LOG is set, each call's arguments are appended to it.
mock_module_downloads() {
  # shellcheck disable=SC2329 # Called by download_and_place_modules.
  curl() {
    if [[ -n "${MOCK_CURL_LOG:-}" ]]; then
      printf '%s\n' "$*" >> "$MOCK_CURL_LOG"
    fi
    local url='' destination=''
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        -o) destination=$2; shift 2 ;;
        https:*) url=$1; shift ;;
        *) shift ;;
      esac
    done
    case "$url" in
      "$IP4DL") printf '%s' "$MOCK_IP4_CONTENT" > "$destination" ;;
      "$IP6DL") printf '%s' "$MOCK_IP6_CONTENT" > "$destination" ;;
      "$SUMSDL") printf '%s' "$MOCK_SUMS" > "$destination" ;;
      *) return 22 ;;
    esac
  }
}
