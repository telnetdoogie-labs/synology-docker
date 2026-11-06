#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/forwarding_fixture.sh
source "$(dirname "$0")/../lib/forwarding_fixture.sh"

# Arrange: a startup script has a daemon-start and postdaemonup anchor.
prepare_forwarding_fixture

# Act: run the forwarding repair twice.
PATH="$iptables_bin:$PATH" bash "$repo_dir/fix_ipforward.sh" >/dev/null
PATH="$iptables_bin:$PATH" bash "$repo_dir/fix_ipforward.sh" >/dev/null

# Expect: each rule appears once, in the right position, and was applied.
expect_file_occurrences "$SYNO_DOCKER_SCRIPT" 'iptables -P FORWARD ACCEPT' 1 'policy rule is inserted only once'
expect_file_occurrences "$SYNO_DOCKER_SCRIPT" 'iptables -C FORWARD -j DOCKER-FORWARD' 1 'forwarding check is inserted only once'
policy_line=$(grep -nF 'iptables -P FORWARD ACCEPT' "$SYNO_DOCKER_SCRIPT" | cut -d: -f1)
daemon_line=$(grep -nFx 'start_docker_daemon' "$SYNO_DOCKER_SCRIPT" | cut -d: -f1)
anchor_line=$(grep -nF "\$DockerUpdaterBin postdaemonup" "$SYNO_DOCKER_SCRIPT" | cut -d: -f1)
expect_success 'policy rule follows daemon start' test "$daemon_line" -lt "$policy_line"
expect_success 'policy rule precedes postdaemonup' test "$policy_line" -lt "$anchor_line"
expect_file_contains "$IPTABLES_LOG" '-P FORWARD ACCEPT' 'policy command was run'
expect_file_contains "$IPTABLES_LOG" '-I FORWARD 1 -j DOCKER-FORWARD' 'forwarding jump was run'
