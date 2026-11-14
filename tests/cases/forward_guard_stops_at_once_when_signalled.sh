#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/forward_guard_fixture.sh
source "$(dirname "$0")/../lib/forward_guard_fixture.sh"

# Arrange: dockerd is up, so the guard is waiting on 'docker events'.
prepare_forward_guard_fixture
write_filter_table '-A FORWARD -j DOCKER-USER' '-A FORWARD -j DOCKER-FORWARD' '-A FORWARD -j FORWARD_FIREWALL'
export DOCKER_EVENTS_MODE=block
PATH="$guard_bin:$PATH" sh "$repo_dir/syno_docker_forward_guard.sh" </dev/null >/dev/null 2>&1 &
guard_pid=$!
for _ in $(seq 50); do
  [ -s "$DOCKER_EVENTS_PID" ] && break
  sleep 0.1
done
events_pid=$(cat "$DOCKER_EVENTS_PID")

# Act: stop the guard the way 'kill <pid>' does, with dockerd still up.
kill "$guard_pid"

# Expect: it exits without waiting for 'docker events' to end, and cleans up after itself.
expect_success 'guard exits on TERM while dockerd is up' timeout 5 tail --pid="$guard_pid" -f /dev/null
expect_success 'guard stops its docker events child' timeout 5 tail --pid="$events_pid" -f /dev/null
expect_file_absent "$SYNO_DOCKER_GUARD_PID_FILE" 'guard removes its pid file'
