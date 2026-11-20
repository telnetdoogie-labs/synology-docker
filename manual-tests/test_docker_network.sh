#!/usr/bin/env bash
# Manual Docker networking smoke test. It creates only uniquely named,
# temporary resources. This is intentionally not a CI test: it validates
# the live Docker/DSM runtime.
#
# Usage: sudo ./manual-tests/test_docker_network.sh
#
# Environment:
#   EGRESS_URL  URL a container fetches to prove outbound forwarding works
#               (default: http://example.com/). Set it to an empty value
#               to skip that check on hosts without internet access.
#
# Exit status: 0 all checks passed, 1 one or more checks failed,
#              2 the test could not be set up.

set -u -o pipefail

NGINX_IMAGE="nginx:alpine"
BUSYBOX_IMAGE="busybox:1.36"
EGRESS_URL="${EGRESS_URL-http://example.com/}"

PREFIX="syno-net-check-$$"

INTERNAL_NETWORK="${PREFIX}-internal"
FORWARDED_NETWORK="${PREFIX}-forwarded"
UNFORWARDED_NETWORK="${PREFIX}-unforwarded"
SHARED_NETWORK="${PREFIX}-shared"

INTERNAL_WEB="${PREFIX}-internal-web"
FORWARDED_WEB="${PREFIX}-forwarded-web"
UNFORWARDED_WEB="${PREFIX}-unforwarded-web"
SHARED_WEB="${PREFIX}-shared-web"

checks=0
failures=0
skipped=0

cleanup() {
  docker rm -f \
    "$INTERNAL_WEB" \
    "$FORWARDED_WEB" \
    "$UNFORWARDED_WEB" \
    "$SHARED_WEB" \
    >/dev/null 2>&1 || true

  docker network rm \
    "$INTERNAL_NETWORK" \
    "$FORWARDED_NETWORK" \
    "$UNFORWARDED_NETWORK" \
    "$SHARED_NETWORK" \
    >/dev/null 2>&1 || true
}

trap cleanup EXIT
trap 'exit 130' INT TERM

result() {
  local label="$1"
  shift

  checks=$((checks + 1))
  if "$@"; then
    printf '✅ %s\n' "$label"
  else
    printf '❌ %s\n' "$label"
    failures=$((failures + 1))
  fi
}

skip() {
  printf 'SKIP %s (%s)\n' "$1" "$2"
  skipped=$((skipped + 1))
}

setup_failed() {
  printf '❌ %s\n' "$1" >&2
  exit 2
}

require_docker() {
  command -v docker >/dev/null 2>&1 &&
    docker info >/dev/null 2>&1
}

ensure_image() {
  local image="$1"

  if docker image inspect "$image" >/dev/null 2>&1; then
    printf 'Using local image: %s\n' "$image"
  else
    printf 'Pulling test image: %s\n' "$image"
    docker pull "$image" >/dev/null 2>&1
  fi
}

container_ip() {
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
    "$1" 2>/dev/null
}

print_environment() {
  local dsm_version kernel_version docker_version ip_forward

  # This is intentionally quiet on non-Synology hosts.
  dsm_version="$(
    if [ -r /etc.defaults/VERSION ]; then
      grep '^productversion=' /etc.defaults/VERSION 2>/dev/null |
        cut -d'"' -f2
    fi
  )"

  kernel_version="$(uname -r 2>/dev/null || printf 'not detected')"
  docker_version="$(docker version --format '{{.Server.Version}}' 2>/dev/null)"
  if [ -z "$docker_version" ]; then
    docker_version="$(docker -v 2>/dev/null || printf 'not detected')"
  fi
  ip_forward="$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || printf 'not detected')"

  printf 'Environment:\n'
  printf '  Kernel: %s\n' "$kernel_version"
  if [ -n "$dsm_version" ]; then
    printf '  DSM: %s\n' "$dsm_version"
  else
    printf '  DSM: not detected\n'
  fi
  printf '  Docker Engine: %s\n' "$docker_version"
  printf '  net.ipv4.ip_forward: %s\n' "$ip_forward"
}

print_forward_rules() {
  local rules

  # Informational only: shows where Docker's jumps sit relative to DSM's
  # firewall chain (see "DSM firewall and published ports" in the README).
  # Needs root and iptables; stays quiet otherwise.
  command -v iptables-save >/dev/null 2>&1 || return 0
  rules="$(iptables-save -t filter 2>/dev/null |
    grep -E '^-A (FORWARD|DEFAULT_FORWARD) ')" || return 0

  printf 'FORWARD rules:\n'
  printf '%s\n' "$rules" | sed 's/^/  /'
}

wait_for_network_settle() {
  printf 'Waiting 20 seconds for Docker/DSM network events to settle'
  for _ in 1 2 3 4; do
    sleep 5
    printf '.'
  done
  printf '\n'
}

probe_blocked() {
  local network="$1" url="$2"

  docker run --rm --network "$network" "$BUSYBOX_IMAGE" \
    wget -T 3 -qO- "$url" >/dev/null 2>&1

  case $? in
    0) return 1 ;; # Incorrect: the request was answered.
    125) return 2 ;; # Docker could not run the probe; do not call that isolation.
    *) return 0 ;; # Correct: the HTTP connection could not be completed.
  esac
}

internal_network_isolated() {
  # Match the reported failure mode: a default-bridge client must not
  # complete a TCP/HTTP request to an --internal-network service.
  probe_blocked bridge "http://${INTERNAL_IP}/"
}

separate_bridges_isolated() {
  # Docker's isolation chains must stop one user-defined bridge from
  # reaching a container on another by IP.
  probe_blocked "$FORWARDED_NETWORK" "http://${UNFORWARDED_IP}/"
}

wait_for_internal_web() {
  # Do not mistake a still-starting Nginx process for network isolation.
  # This confirms only that the target is serving HTTP in its own namespace.
  for _ in {1..10}; do
    if docker exec "$INTERNAL_WEB" \
        wget -T 1 -qO- http://127.0.0.1/ >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

host_reaches_published_port() {
  # Uses the host network namespace without requiring wget/curl on DSM itself.
  docker run --rm --network host "$BUSYBOX_IMAGE" \
    wget -T 3 -qO- "http://127.0.0.1:${FORWARDED_PORT}/" \
    >/dev/null 2>&1
}

container_has_no_published_port() {
  # The host can normally route directly to a container IP.
  # This checks the actual meaning of "no forward": no host-port mapping.
  [ -z "$(docker port "$UNFORWARDED_WEB" 2>/dev/null)" ]
}

same_network_containers_reach_each_other() {
  # User-defined bridge networks provide scoped Docker DNS.
  docker run --rm --network "$SHARED_NETWORK" "$BUSYBOX_IMAGE" \
    wget -T 3 -qO- "http://${SHARED_WEB}/" >/dev/null 2>&1
}

container_reaches_outside() {
  # Outbound traffic from a bridge container crosses the FORWARD chain, so
  # this fails if Docker's FORWARD jumps were removed after a container event.
  docker run --rm --network "$FORWARDED_NETWORK" "$BUSYBOX_IMAGE" \
    wget -T 5 -qO- "$EGRESS_URL" >/dev/null 2>&1
}

printf 'Preparing Docker networking validation...\n'

if ! require_docker; then
  setup_failed 'Docker daemon is not available to this user (on DSM, run with sudo).'
fi

print_environment
print_forward_rules

printf 'Checking test images...\n'
if ! ensure_image "$NGINX_IMAGE" || ! ensure_image "$BUSYBOX_IMAGE"; then
  setup_failed 'Required test image could not be pulled or inspected.'
fi

printf 'Creating temporary networks and containers...\n'
if ! docker network create --internal "$INTERNAL_NETWORK" >/dev/null 2>&1 ||
   ! docker run -d --rm --name "$INTERNAL_WEB" \
       --network "$INTERNAL_NETWORK" "$NGINX_IMAGE" >/dev/null 2>&1; then
  setup_failed 'Could not create the temporary internal-network test resources.'
fi

INTERNAL_IP="$(container_ip "$INTERNAL_WEB")"
if [ -z "$INTERNAL_IP" ]; then
  setup_failed 'Could not determine the temporary internal container IP.'
fi

printf 'Waiting for the internal test web server to become ready...\n'
if ! wait_for_internal_web; then
  setup_failed 'The temporary internal test web server did not become ready.'
fi

printf 'Running immediate internal-network check...\n'
result \
  'Internal network is immediately isolated from the default bridge' \
  internal_network_isolated

printf 'Creating remaining temporary networks and containers...\n'
if ! docker network create "$FORWARDED_NETWORK" >/dev/null 2>&1 ||
   ! docker network create "$UNFORWARDED_NETWORK" >/dev/null 2>&1 ||
   ! docker network create "$SHARED_NETWORK" >/dev/null 2>&1 ||
   ! docker run -d --rm --name "$FORWARDED_WEB" \
       --network "$FORWARDED_NETWORK" \
       -p 127.0.0.1::80 \
       "$NGINX_IMAGE" >/dev/null 2>&1 ||
   ! docker run -d --rm --name "$UNFORWARDED_WEB" \
       --network "$UNFORWARDED_NETWORK" \
       "$NGINX_IMAGE" >/dev/null 2>&1 ||
   ! docker run -d --rm --name "$SHARED_WEB" \
       --network "$SHARED_NETWORK" \
       "$NGINX_IMAGE" >/dev/null 2>&1; then
  setup_failed 'Could not create the temporary Docker test resources.'
fi

FORWARDED_BINDING="$(docker port "$FORWARDED_WEB" 80/tcp 2>/dev/null)"
FORWARDED_PORT="${FORWARDED_BINDING##*:}"

if [ -z "$FORWARDED_BINDING" ] ||
   [ "$FORWARDED_PORT" = "$FORWARDED_BINDING" ]; then
  setup_failed 'Could not determine the temporary published port.'
fi

UNFORWARDED_IP="$(container_ip "$UNFORWARDED_WEB")"
if [ -z "$UNFORWARDED_IP" ]; then
  setup_failed 'Could not determine the temporary unforwarded container IP.'
fi

wait_for_network_settle

printf 'Running connectivity checks...\n'
result \
  'Internal network remains isolated after Docker/DSM events settle' \
  internal_network_isolated

result \
  'Containers on separate bridges cannot reach each other' \
  separate_bridges_isolated

result \
  'Host namespace reaches a published container port' \
  host_reaches_published_port

result \
  'Unpublished container has no host-port mapping' \
  container_has_no_published_port

result \
  'Containers on the same bridge reach each other without published ports' \
  same_network_containers_reach_each_other

if [ -n "$EGRESS_URL" ]; then
  result \
    "Bridge container reaches ${EGRESS_URL} (outbound forwarding)" \
    container_reaches_outside
else
  skip 'Bridge container outbound forwarding' 'EGRESS_URL is empty'
fi

printf 'Cleaning up temporary test resources...\n'
cleanup
trap - EXIT

printf '\n%d passed, %d failed, %d skipped\n' \
  "$((checks - failures))" "$failures" "$skipped"

[ "$failures" -eq 0 ]
