#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/forward_guard_fixture.sh
source "$(dirname "$0")/../lib/forward_guard_fixture.sh"

# Arrange: placement after the DSM firewall (quoted, CRLF line end) and DSM has just rewritten the table.
prepare_forward_guard_fixture
printf 'placement="after-firewall"\r\n' > "$SYNO_DOCKER_GUARD_CONF"
write_filter_table '-A FORWARD -j FORWARD_FIREWALL'

# Act/expect: both jumps go right after DSM's chain, DOCKER-USER first.
run_guard_once
expect_eq $'-I FORWARD 2 -j DOCKER-USER\n-I FORWARD 3 -j DOCKER-FORWARD' "$(cat "$IPTABLES_LOG")" 'jumps restored after FORWARD_FIREWALL'

# Arrange: the startup script and dockerd left the jumps ahead of DSM's chain.
write_filter_table '-A FORWARD -j DOCKER-USER' '-A FORWARD -j DOCKER-FORWARD' '-A FORWARD -j FORWARD_FIREWALL'
write_filter_table_after_delete '-A FORWARD -j FORWARD_FIREWALL'

# Act/expect: they are moved behind it.
run_guard_once
expect_eq $'-D FORWARD -j DOCKER-USER\n-D FORWARD -j DOCKER-FORWARD\n-I FORWARD 2 -j DOCKER-USER\n-I FORWARD 3 -j DOCKER-FORWARD' \
  "$(cat "$IPTABLES_LOG")" 'jumps ahead of FORWARD_FIREWALL are moved after it'

# Arrange/act/expect: jumps already after DSM's chain are left alone.
write_filter_table '-A FORWARD -j FORWARD_FIREWALL' '-A FORWARD -j DOCKER-USER' '-A FORWARD -j DOCKER-FORWARD'
run_guard_once
expect_eq '' "$(cat "$IPTABLES_LOG")" 'placed jumps are not touched'

# Arrange/act/expect: with the DSM firewall off there is no chain to follow, so the jumps go first.
write_filter_table '-A FORWARD -i lo -j ACCEPT'
run_guard_once
expect_eq $'-I FORWARD 1 -j DOCKER-USER\n-I FORWARD 2 -j DOCKER-FORWARD' "$(cat "$IPTABLES_LOG")" 'no FORWARD_FIREWALL means first'

# Arrange: back to the default, with the jumps still after DSM's chain.
set_placement 'placement=first'
write_filter_table '-A FORWARD -j FORWARD_FIREWALL' '-A FORWARD -j DOCKER-USER' '-A FORWARD -j DOCKER-FORWARD'
write_filter_table_after_delete '-A FORWARD -j FORWARD_FIREWALL'

# Act/expect: they are moved back ahead of it.
run_guard_once
expect_eq $'-D FORWARD -j DOCKER-USER\n-D FORWARD -j DOCKER-FORWARD\n-I FORWARD 1 -j DOCKER-USER\n-I FORWARD 2 -j DOCKER-FORWARD' \
  "$(cat "$IPTABLES_LOG")" 'placement=first moves the jumps back ahead'
