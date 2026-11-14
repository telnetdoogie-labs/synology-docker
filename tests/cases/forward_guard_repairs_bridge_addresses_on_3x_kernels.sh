#!/bin/bash
# On 3.x kernels a bridge Docker creates drops frames sent to its own address until that address is changed and
# changed back (issue #116). The guard does that once for each Docker bridge, and for bridges created later.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/forward_guard_fixture.sh
source "$(dirname "$0")/../lib/forward_guard_fixture.sh"

wait_for_ip_calls() {
  for _ in $(seq 50); do
    [ "$(wc -l < "$IP_LOG")" -ge "$1" ] && return 0
    sleep 0.1
  done
  return 1
}

# Arrange: Docker's default bridge and a user-defined network's bridge, next to devices that are not Docker's.
prepare_forward_guard_fixture
write_filter_table '-A FORWARD -j DOCKER-USER' '-A FORWARD -j DOCKER-FORWARD'
add_net_device docker0 31 '92:62:e6:3c:e3:d5' bridge
add_net_device br-0123456789ab 32 '02:00:00:00:00:01' bridge
add_net_device br-lan 5 '00:11:32:aa:bb:cc' bridge
add_net_device eth0 2 '00:11:32:aa:bb:cd'

# Act/expect: a 4.x kernel records the address itself, so nothing is changed.
run_guard_once
expect_eq '' "$(cat "$IP_LOG")" 'bridges are left alone on a 4.x kernel'

# Act: the same check by hand on a 3.10 kernel.
export SYNO_DOCKER_GUARD_KERNEL='3.10.108'
run_guard_once

# Expect: each Docker bridge moved to a spare address and back; a bridge already on the spare gets another one.
expect_eq 'link set dev docker0 address 02:00:00:00:00:01
link set dev docker0 address 92:62:e6:3c:e3:d5
link set dev br-0123456789ab address 02:00:00:00:00:02
link set dev br-0123456789ab address 02:00:00:00:00:01' "$(cat "$IP_LOG")" 'each Docker bridge is changed and changed back'
expect_eq '92:62:e6:3c:e3:d5' "$(cat "$SYNO_DOCKER_GUARD_SYS_NET/docker0/address")" 'docker0 keeps its address'
expect_file_absent "$SYNO_DOCKER_GUARD_BRIDGE_STATE" 'a run by hand keeps no record'

# Act: start the guard the way start-stop-status does, and let it check more than once.
: > "$IP_LOG"
export DOCKER_EVENTS_MODE=block
PATH="$guard_bin:$PATH" sh "$repo_dir/syno_docker_forward_guard.sh" </dev/null >/dev/null 2>&1 &
guard_pid=$!
expect_success 'running guard repairs both bridges' wait_for_ip_calls 4
sleep 2.5

# Expect: both bridges were repaired once, not on every check.
expect_eq 4 "$(wc -l < "$IP_LOG")" 'a repaired bridge is not changed again'

# Act: a network is created while dockerd runs, and docker0 is recreated under a new ifindex.
add_net_device br-ba9876543210 40 '1e:db:9c:6e:7b:eb' bridge
add_net_device docker0 41 '92:62:e6:3c:e3:d5' bridge
expect_success 'running guard repairs new bridges' wait_for_ip_calls 8

# Expect: only the new and the recreated bridge were changed.
expect_file_occurrences "$IP_LOG" 'link set dev br-ba9876543210 address 1e:db:9c:6e:7b:eb' 1 'a bridge created later is repaired'
expect_file_occurrences "$IP_LOG" 'link set dev docker0 address 92:62:e6:3c:e3:d5' 2 'a recreated bridge is repaired again'
expect_file_occurrences "$IP_LOG" 'link set dev br-0123456789ab' 2 'an unchanged bridge is left alone'

# Act: dockerd stops.
kill "$(cat "$DOCKER_EVENTS_PID")"

# Expect: the guard exits and removes its record with its pid file.
expect_success 'guard exits when dockerd stops' timeout 10 tail --pid="$guard_pid" -f /dev/null
expect_file_absent "$SYNO_DOCKER_GUARD_BRIDGE_STATE" 'guard removes its bridge record'
