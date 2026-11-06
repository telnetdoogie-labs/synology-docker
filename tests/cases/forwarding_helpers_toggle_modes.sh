#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/forwarding_fixture.sh
source "$(dirname "$0")/../lib/forwarding_fixture.sh"

# Arrange: the startup script starts with the policy-based forwarding fix.
prepare_forwarding_fixture
PATH="$iptables_bin:$PATH" bash "$repo_dir/fix_ipforward.sh" >/dev/null

# Act/expect: switch to per-interface docker0 rules.
PATH="$iptables_bin:$PATH" bash "$repo_dir/switch_forward.sh" >/dev/null
expect_file_occurrences "$SYNO_DOCKER_SCRIPT" 'iptables -I FORWARD -i docker0 -j ACCEPT' 1 'docker0 input accept inserted'
expect_file_occurrences "$SYNO_DOCKER_SCRIPT" 'iptables -I FORWARD -o docker0 -j ACCEPT' 1 'docker0 output accept inserted'
expect_file_occurrences "$SYNO_DOCKER_SCRIPT" 'iptables -P FORWARD ACCEPT' 0 'policy rule removed when switching modes'

# Act/expect: switch back to the policy rule.
PATH="$iptables_bin:$PATH" bash "$repo_dir/switch_forward.sh" >/dev/null
expect_file_occurrences "$SYNO_DOCKER_SCRIPT" 'iptables -P FORWARD ACCEPT' 1 'policy rule restored on second switch'
expect_file_occurrences "$SYNO_DOCKER_SCRIPT" 'iptables -I FORWARD -i docker0 -j ACCEPT' 0 'docker0 rules removed on second switch'
