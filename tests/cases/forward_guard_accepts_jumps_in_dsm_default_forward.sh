#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/forward_guard_fixture.sh
source "$(dirname "$0")/../lib/forward_guard_fixture.sh"

# Arrange: DSM's iptables put the guard's jumps in DEFAULT_FORWARD, hooked after DSM's chain (issue #134, DS220+).
prepare_forward_guard_fixture
write_filter_table '-A FORWARD -j FORWARD_FIREWALL' '-A FORWARD -j DEFAULT_FORWARD' \
  '-A DEFAULT_FORWARD -j DOCKER-USER' '-A DEFAULT_FORWARD -j DOCKER-FORWARD'

# Act/expect: they count as present with the default placement, so nothing is inserted again.
run_guard_once
expect_eq '' "$(cat "$IPTABLES_LOG")" 'jumps in DEFAULT_FORWARD are not inserted again'

# Act/expect: the same with placement after the DSM firewall.
set_placement 'placement=after-firewall'
run_guard_once
expect_eq '' "$(cat "$IPTABLES_LOG")" 'jumps in DEFAULT_FORWARD are left alone after the firewall'

# Arrange: only DOCKER-USER is in DEFAULT_FORWARD, second in that chain.
write_filter_table '-A FORWARD -j FORWARD_FIREWALL' '-A FORWARD -j DEFAULT_FORWARD' \
  '-A DEFAULT_FORWARD -i lo -j ACCEPT' '-A DEFAULT_FORWARD -j DOCKER-USER'

# Act/expect: DSM's iptables counts the position within DEFAULT_FORWARD, so DOCKER-FORWARD goes right after DOCKER-USER
# there, with either placement.
run_guard_once
expect_eq '-I FORWARD 3 -j DOCKER-FORWARD' "$(cat "$IPTABLES_LOG")" 'DOCKER-FORWARD restored after DOCKER-USER in DEFAULT_FORWARD'
set_placement 'placement=first'
write_filter_table '-A FORWARD -j FORWARD_FIREWALL' '-A FORWARD -j DEFAULT_FORWARD' '-A DEFAULT_FORWARD -j DOCKER-USER'
run_guard_once
expect_eq '-I FORWARD 2 -j DOCKER-FORWARD' "$(cat "$IPTABLES_LOG")" 'DOCKER-FORWARD is not put ahead of DOCKER-USER'

# Arrange: only DOCKER-FORWARD is in DEFAULT_FORWARD, second in that chain.
write_filter_table '-A FORWARD -j FORWARD_FIREWALL' '-A FORWARD -j DEFAULT_FORWARD' \
  '-A DEFAULT_FORWARD -i lo -j ACCEPT' '-A DEFAULT_FORWARD -j DOCKER-FORWARD'

# Act/expect: DOCKER-USER takes its position, which pushes DOCKER-FORWARD down one, with either placement.
run_guard_once
expect_eq '-I FORWARD 2 -j DOCKER-USER' "$(cat "$IPTABLES_LOG")" 'DOCKER-USER restored ahead of DOCKER-FORWARD in DEFAULT_FORWARD'
set_placement 'placement=after-firewall'
write_filter_table '-A FORWARD -j FORWARD_FIREWALL' '-A FORWARD -j DEFAULT_FORWARD' '-A DEFAULT_FORWARD -j DOCKER-FORWARD'
run_guard_once
expect_eq '-I FORWARD 1 -j DOCKER-USER' "$(cat "$IPTABLES_LOG")" 'DOCKER-USER is not put behind DOCKER-FORWARD'

# Arrange: DSM rewrote the table; a leftover DEFAULT_FORWARD chain still lists the jumps, but FORWARD no longer jumps
# to it.
set_placement 'placement=first'
write_filter_table '-A FORWARD -j FORWARD_FIREWALL' '-A DEFAULT_FORWARD -j DOCKER-USER' '-A DEFAULT_FORWARD -j DOCKER-FORWARD'

# Act/expect: unreachable jumps do not count, so both are restored.
run_guard_once
expect_eq $'-I FORWARD 1 -j DOCKER-USER\n-I FORWARD 2 -j DOCKER-FORWARD' "$(cat "$IPTABLES_LOG")" 'unhooked DEFAULT_FORWARD does not count'
