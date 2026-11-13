#!/bin/sh
# Keeps the FORWARD jumps into Docker's chains (DOCKER-USER, then DOCKER-FORWARD) in place on DSM, for IPv4 and IPv6.
#
# With the DSM firewall enabled, DSM replaces the whole filter table a few seconds after every container network
# change (and whenever the firewall reloads). Docker's chains survive, but the FORWARD jumps into them do not, so
# DOCKER-USER rules and 'internal: true' network isolation stop applying. Container Manager's start-stop-status starts
# this guard once dockerd is up; it checks the jumps every few seconds and exits when dockerd stops.
#
# Placement is read from <package>/etc/syno_docker_forward_guard.conf on every check:
#   placement=first           (default) jumps ahead of DSM's '-j FORWARD_FIREWALL', so Docker's rules decide first and
#                             the DSM firewall does not apply to published container ports. Standard Docker behavior.
#   placement=after-firewall  jumps right after '-j FORWARD_FIREWALL', so traffic must pass the DSM firewall, then
#                             Docker's rules. Without a FORWARD_FIREWALL jump (DSM firewall off), the same as 'first'.
#
# The updater copies this file next to start-stop-status. Run by hand with '--once' to repair the jumps a single time.
# Must stay POSIX sh: it runs from DSM's startup script.

# Installed in <package>/scripts: the docker client is at <package>/target/usr/bin, the settings in <package>/etc.
docker_bin=${SYNO_DOCKER_GUARD_DOCKER:-${0%/*}/../target/usr/bin/docker}
conf_file=${SYNO_DOCKER_GUARD_CONF:-${0%/*}/../etc/syno_docker_forward_guard.conf}
pid_file=${SYNO_DOCKER_GUARD_PID_FILE:-/var/run/syno_docker_forward_guard.pid}
interval=${SYNO_DOCKER_GUARD_INTERVAL:-2}

# Sets 'rules', 'forward' (FORWARD rules in order, so line N is rule N) and 'firewall' (rule number of the
# FORWARD_FIREWALL jump, empty without one) from '<tool>-save'. iptables-save is used because 'iptables -C' has given
# wrong answers on DSM.
read_forward() {
  rules=$("$1-save" -t filter 2>/dev/null) || return 1
  forward=$(printf '%s\n' "$rules" | grep '^-A FORWARD ')
  firewall=$(rule_numbers FORWARD_FIREWALL | head -n 1)
}

# Rule numbers of the FORWARD jumps to a chain, one per line.
rule_numbers() {
  printf '%s\n' "$forward" | grep -nx -- "-A FORWARD -j $1" | cut -d: -f1
}

# Whether rule number $1 is where the chosen placement wants the jumps.
in_place() {
  [ -z "$firewall" ] && return 0
  if [ "$placement" = after-firewall ]; then
    [ "$1" -gt "$firewall" ]
  else
    [ "$1" -lt "$firewall" ]
  fi
}

# First rule number of the jumps to a chain that is in place, empty if none is.
placed_jump() {
  for number in $(rule_numbers "$1"); do
    if in_place "$number"; then
      echo "$number"
      return
    fi
  done
}

# Puts back whichever jump is missing, in Docker's order (DOCKER-USER first, DOCKER-FORWARD right after it) and at the
# chosen placement. A jump on the wrong side of FORWARD_FIREWALL is removed, every copy of it, then inserted again.
ensure_jumps() {
  tool=$1
  read_forward "$tool" || return 0
  # dockerd has not created its chain yet (or it was cleared on stop): there is nothing to jump to.
  printf '%s\n' "$rules" | grep -q '^:DOCKER-FORWARD ' || return 0
  placement=$(sed -n 's/^placement=//p' "$conf_file" 2>/dev/null | tail -n 1 | tr -d " \t\r\"'")

  moved=''
  for chain in DOCKER-USER DOCKER-FORWARD; do
    for number in $(rule_numbers "$chain"); do
      in_place "$number" && continue
      for _ in $(rule_numbers "$chain"); do
        "$tool" -D FORWARD -j "$chain" || break
      done
      moved=1
      break
    done
  done
  if [ -n "$moved" ]; then
    read_forward "$tool" || return 0
  fi

  start=0
  if [ -n "$firewall" ] && [ "$placement" = after-firewall ]; then
    start=$firewall
  fi
  user=$(placed_jump DOCKER-USER)
  if [ -z "$user" ] && printf '%s\n' "$rules" | grep -q '^:DOCKER-USER '; then
    user=$((start + 1))
    "$tool" -I FORWARD "$user" -j DOCKER-USER || return 1
    # Everything from that position on moved down one.
    if [ -n "$firewall" ] && [ "$firewall" -ge "$user" ]; then
      firewall=$((firewall + 1))
    fi
    forward=$(printf '%s\n' "$forward" | sed "${user}i\\
-A FORWARD -j DOCKER-USER")
    [ -n "$forward" ] || forward='-A FORWARD -j DOCKER-USER'
  fi
  if [ -z "$(placed_jump DOCKER-FORWARD)" ]; then
    "$tool" -I FORWARD $((${user:-$start} + 1)) -j DOCKER-FORWARD || return 1
  fi
  return 0
}

ensure_all_jumps() {
  status=0
  ensure_jumps iptables || status=1
  ensure_jumps ip6tables || status=1
  return "$status"
}

if [ "${1:-}" = '--once' ]; then
  ensure_all_jumps
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

# Whether dockerd still answers. 'timeout' keeps a hung daemon from stalling the guard, when it is available.
docker_answers() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 30 "$docker_bin" version >/dev/null 2>&1
  else
    "$docker_bin" version >/dev/null 2>&1
  fi
}

# 'docker events' runs for as long as dockerd does, so the guard's lifetime follows the daemon's. If it ends while
# dockerd still answers (a dropped connection, not a stop), the guard keeps going.
while :; do
  (
    while :; do
      ensure_all_jumps
      sleep "$interval"
    done
  ) &
  checker_pid=$!
  "$docker_bin" events --format '{{.Type}}' >/dev/null 2>&1
  kill "$checker_pid" 2>/dev/null
  checker_pid=''
  sleep "$interval"
  docker_answers || exit 0
done
