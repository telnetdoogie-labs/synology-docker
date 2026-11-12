#!/bin/sh
# Keeps the FORWARD jumps into Docker's chains (DOCKER-USER, then DOCKER-FORWARD) in place on DSM.
#
# With the DSM firewall enabled, DSM replaces the whole filter table a few seconds after every container network
# change (and whenever the firewall reloads). Docker's chains survive, but the FORWARD jumps into them do not, so
# DOCKER-USER rules and 'internal: true' network isolation stop applying. Container Manager's start-stop-status starts
# this guard once dockerd is up; it checks the jumps every few seconds and exits when dockerd stops.
#
# The updater copies this file next to start-stop-status. Run by hand with '--once' to repair the jumps a single time.
# Must stay POSIX sh: it runs from DSM's startup script.

# Installed in <package>/scripts, so the package's docker client is at <package>/target/usr/bin/docker.
docker_bin=${SYNO_DOCKER_GUARD_DOCKER:-${0%/*}/../target/usr/bin/docker}
pid_file=${SYNO_DOCKER_GUARD_PID_FILE:-/var/run/syno_docker_forward_guard.pid}
interval=${SYNO_DOCKER_GUARD_INTERVAL:-2}

# Puts back whichever jump is missing, keeping Docker's order: DOCKER-USER first, DOCKER-FORWARD right after it.
# iptables-save is used for the check because 'iptables -C' has given wrong answers on DSM.
ensure_jumps() {
  rules=$(iptables-save -t filter 2>/dev/null) || return 0
  # dockerd has not created its chain yet (or it was cleared on stop): there is nothing to jump to.
  printf '%s\n' "$rules" | grep -q '^:DOCKER-FORWARD ' || return 0
  forward=$(printf '%s\n' "$rules" | grep '^-A FORWARD ')
  if printf '%s\n' "$rules" | grep -q '^:DOCKER-USER ' &&
    ! printf '%s\n' "$forward" | grep -qx -- '-A FORWARD -j DOCKER-USER'; then
    iptables -I FORWARD 1 -j DOCKER-USER || return 1
    forward=$(printf '%s\n%s' '-A FORWARD -j DOCKER-USER' "$forward")
  fi
  if ! printf '%s\n' "$forward" | grep -qx -- '-A FORWARD -j DOCKER-FORWARD'; then
    position=$(printf '%s\n' "$forward" | grep -nx -- '-A FORWARD -j DOCKER-USER' | head -n 1 | cut -d: -f1)
    iptables -I FORWARD $((${position:-0} + 1)) -j DOCKER-FORWARD || return 1
  fi
  return 0
}

if [ "${1:-}" = '--once' ]; then
  ensure_jumps
  exit
fi

# Only one guard at a time: Container Manager can be restarted, and the helpers can be run more than once.
if [ -f "$pid_file" ]; then
  running=$(cat "$pid_file" 2>/dev/null)
  if [ -n "$running" ] && grep -q syno_docker_forward_guard "/proc/$running/cmdline" 2>/dev/null; then
    exit 0
  fi
fi
echo "$$" > "$pid_file" || exit 1

checker_pid=''
cleanup() {
  [ -n "$checker_pid" ] && kill "$checker_pid" 2>/dev/null
  rm -f "$pid_file"
}
trap cleanup EXIT
trap 'exit 0' HUP INT TERM

# 'docker events' runs for as long as dockerd does, so the guard's lifetime follows the daemon's. If it ends while
# dockerd still answers (a dropped connection, not a stop), the guard keeps going.
while :; do
  (
    while :; do
      ensure_jumps
      sleep "$interval"
    done
  ) &
  checker_pid=$!
  "$docker_bin" events --format '{{.Type}}' >/dev/null 2>&1
  kill "$checker_pid" 2>/dev/null
  checker_pid=''
  sleep "$interval"
  timeout 30 "$docker_bin" version >/dev/null 2>&1 || exit 0
done
