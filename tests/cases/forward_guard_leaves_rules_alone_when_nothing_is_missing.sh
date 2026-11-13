#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/forward_guard_fixture.sh
source "$(dirname "$0")/../lib/forward_guard_fixture.sh"

# Arrange: both jumps are already in FORWARD.
prepare_forward_guard_fixture
write_filter_table '-A FORWARD -j DOCKER-USER' '-A FORWARD -j DOCKER-FORWARD' '-A FORWARD -j FORWARD_FIREWALL'

# Act/expect: a check changes nothing.
run_guard_once
expect_eq '' "$(cat "$IPTABLES_LOG")" 'present jumps are not inserted again'

# Arrange: dockerd has not created its chains (or they were cleared on stop).
printf '*filter\n:FORWARD ACCEPT [0:0]\n-A FORWARD -j FORWARD_FIREWALL\nCOMMIT\n' > "$IPTABLES_SAVE_OUTPUT"

# Act/expect: no jump to a chain that does not exist.
run_guard_once
expect_eq '' "$(cat "$IPTABLES_LOG")" 'no jump added without Docker chains'
