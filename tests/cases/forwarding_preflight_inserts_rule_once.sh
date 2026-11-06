#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: the startup script has the required forwarding anchor.
init_update_fixture
prepare_installed_files
cp "$repo_dir/test_file/start-stop-status" "$SYNO_DOCKER_SCRIPT"
skip_docker_update='false'
command=''

# Act: run the script update twice.
execute_update_script >/dev/null
execute_update_script >/dev/null

# Expect: the forwarding check is inserted exactly once.
expect_file_contains "$SYNO_DOCKER_SCRIPT" 'iptables -C FORWARD -j DOCKER-FORWARD' 'forwarding rule inserted'
expect_eq 1 "$(grep -c 'iptables -C FORWARD -j DOCKER-FORWARD' "$SYNO_DOCKER_SCRIPT")" 'rule is inserted only once'
