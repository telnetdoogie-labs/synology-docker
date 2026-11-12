#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/forward_guard_fixture.sh
source "$(dirname "$0")/../lib/forward_guard_fixture.sh"

# Arrange: DSM rewrote the filter table; FORWARD only jumps to its own firewall chain (issue #134).
prepare_forward_guard_fixture
write_filter_table '-A FORWARD -j FORWARD_FIREWALL'

# Act: one guard check.
run_guard_once

# Expect: both jumps are put back ahead of DSM's chain, DOCKER-USER first as Docker orders them.
expect_eq $'-I FORWARD 1 -j DOCKER-USER\n-I FORWARD 2 -j DOCKER-FORWARD' "$(cat "$IPTABLES_LOG")" 'both jumps restored in Docker order'

# Arrange: only DOCKER-FORWARD is missing, and DOCKER-USER sits second.
: > "$IPTABLES_LOG"
write_filter_table '-A FORWARD -j FORWARD_FIREWALL' '-A FORWARD -j DOCKER-USER'

# Act: one guard check.
run_guard_once

# Expect: DOCKER-FORWARD goes directly after DOCKER-USER; DOCKER-USER is not duplicated.
expect_eq '-I FORWARD 3 -j DOCKER-FORWARD' "$(cat "$IPTABLES_LOG")" 'DOCKER-FORWARD restored after DOCKER-USER'
