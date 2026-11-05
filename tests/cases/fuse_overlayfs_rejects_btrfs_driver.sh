#!/bin/bash
# Never switch an existing btrfs installation to fuse-overlayfs and hide its images.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: a disposable package config using a supported non-aufs driver.
mkdir -p /var/packages/ContainerManager/etc
cp "$repo_dir/test_file/dockerd.json" /var/packages/ContainerManager/etc/dockerd.json
original_json="$test_tmp_dir/original-dockerd.json"
cp /var/packages/ContainerManager/etc/dockerd.json "$original_json"
# The installer reads this path while defining its constants; keep it inert.
mkdir -p /usr/local/etc/rc.d
: > /usr/local/etc/rc.d/containerd-fuse-overlayfs.sh
# Source the real installer functions without executing its live install main.
# The file ends its declarations with a '# Main' marker; fail closed if it moves.
grep -Fxq '# Main' "$repo_dir/install_fuse_overlayfs.sh" || { printf 'FAIL: fuse installer main boundary missing\n' >&2; exit 1; }
set -- ''
# shellcheck source=install_fuse_overlayfs.sh
source <(sed '/^# Main$/,$d' "$repo_dir/install_fuse_overlayfs.sh")

# Act: ask the real installer's storage-driver guard to evaluate btrfs.
if output=$(check_storage_driver 2>&1); then
  printf 'FAIL: fuse-overlayfs installer accepted a btrfs driver switch\n' >&2
  exit 1
fi

# Expect: the guard explains why, with no changes to the existing config.
expect_contains "$output" "Docker uses the 'btrfs' storage driver" 'btrfs driver blocks fuse overlay switch'
expect_contains "$output" 'switching would hide all existing images and containers' 'failure explains the data visibility risk'
expect_files_equal "$original_json" "$SYNO_DOCKER_JSON" 'unsafe driver switch leaves config unchanged'
