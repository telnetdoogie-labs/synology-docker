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
}
