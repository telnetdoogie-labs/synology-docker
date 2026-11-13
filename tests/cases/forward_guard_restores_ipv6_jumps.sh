#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/forward_guard_fixture.sh
source "$(dirname "$0")/../lib/forward_guard_fixture.sh"

# Arrange: the IPv4 jumps are in place, but DSM dropped the IPv6 ones.
prepare_forward_guard_fixture
write_filter_table '-A FORWARD -j DOCKER-USER' '-A FORWARD -j DOCKER-FORWARD' '-A FORWARD -j FORWARD_FIREWALL'
write_table "$IP6TABLES_SAVE_OUTPUT" '-A FORWARD -j FORWARD_FIREWALL'

# Act: one guard check.
run_guard_once

# Expect: only ip6tables is changed, the same way.
expect_eq '' "$(cat "$IPTABLES_LOG")" 'IPv4 left alone'
expect_eq $'-I FORWARD 1 -j DOCKER-USER\n-I FORWARD 2 -j DOCKER-FORWARD' "$(cat "$IP6TABLES_LOG")" 'IPv6 jumps restored'

# Arrange: Docker has no IPv6 chains (IPv6 off in Docker).
: > "$IP6TABLES_LOG"
printf '*filter\n:FORWARD ACCEPT [0:0]\n-A FORWARD -j FORWARD_FIREWALL\nCOMMIT\n' > "$IP6TABLES_SAVE_OUTPUT"

# Act/expect: nothing is added to ip6tables.
run_guard_once
expect_eq '' "$(cat "$IP6TABLES_LOG")" 'no IPv6 jump without Docker IPv6 chains'
