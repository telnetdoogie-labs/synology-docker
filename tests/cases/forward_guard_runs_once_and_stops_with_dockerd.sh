#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/forward_guard_fixture.sh
source "$(dirname "$0")/../lib/forward_guard_fixture.sh"

# Arrange: dockerd is up ('docker events' keeps running) and DSM has dropped the jumps.
prepare_forward_guard_fixture
write_filter_table '-A FORWARD -j FORWARD_FIREWALL'
export DOCKER_EVENTS_MODE=block

# Act: start the guard the way start-stop-status does.
PATH="$guard_bin:$PATH" sh "$repo_dir/syno_docker_forward_guard.sh" </dev/null >/dev/null 2>&1 &
guard_pid=$!
for _ in $(seq 50); do
  grep -q DOCKER-FORWARD "$IPTABLES_LOG" && break
  sleep 0.1
done

# Expect: it repaired the jumps and recorded itself.
expect_file_contains "$IPTABLES_LOG" '-I FORWARD 2 -j DOCKER-FORWARD' 'running guard restores the jumps'
expect_eq "$guard_pid" "$(cat "$SYNO_DOCKER_GUARD_PID_FILE")" 'running guard writes its pid file'

# Act/expect: a second start (Container Manager restarted, helper rerun) leaves the first guard in charge.
expect_success 'second guard exits at once' timeout 5 env PATH="$guard_bin:$PATH" sh "$repo_dir/syno_docker_forward_guard.sh"
expect_eq "$guard_pid" "$(cat "$SYNO_DOCKER_GUARD_PID_FILE")" 'second guard does not take over'

# Act: dockerd stops, so 'docker events' ends and 'docker version' fails.
kill "$(cat "$DOCKER_EVENTS_PID")"

# Expect: the guard exits on its own and removes its pid file.
expect_success 'guard exits when dockerd stops' timeout 10 tail --pid="$guard_pid" -f /dev/null
expect_file_absent "$SYNO_DOCKER_GUARD_PID_FILE" 'guard removes its pid file'
