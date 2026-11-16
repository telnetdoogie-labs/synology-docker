#!/usr/bin/env bash
# Manual Docker networking smoke test. It creates only uniquely named,
# temporary resources. This is intentionally not a CI test: it validates
# the live Docker/DSM runtime.

set -u -o pipefail

NGINX_IMAGE="nginx:alpine"
BUSYBOX_IMAGE="busybox:1.36"

PREFIX="syno-net-check-$$"

INTERNAL_NETWORK="${PREFIX}-internal"
FORWARDED_NETWORK="${PREFIX}-forwarded"
UNFORWARDED_NETWORK="${PREFIX}-unforwarded"
SHARED_NETWORK="${PREFIX}-shared"

INTERNAL_WEB="${PREFIX}-internal-web"
FORWARDED_WEB="${PREFIX}-forwarded-web"
UNFORWARDED_WEB="${PREFIX}-unforwarded-web"
SHARED_WEB="${PREFIX}-shared-web"

failures=0

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

  if "$@"; then
    printf '✅ %s\n' "$label"
  else
    printf '❌ %s\n' "$label"
    failures=$((failures + 1))
  fi
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

print_environment() {
  local dsm_version kernel_version docker_version

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

  printf 'Environment:\n'
  printf '  Kernel: %s\n' "$kernel_version"
  if [ -n "$dsm_version" ]; then
    printf '  DSM: %s\n' "$dsm_version"
  else
    printf '  DSM: not detected\n'
  fi
  printf '  Docker Engine: %s\n' "$docker_version"
}

wait_for_network_settle() {
  printf 'Waiting 20 seconds for Docker/DSM network events to settle'
  for _ in 1 2 3 4; do
    sleep 5
    printf '.'
  done
  printf '\n'
}

internal_network_isolated() {
  # ping exits 1 when the target cannot be reached.
  # Exit 125 would mean Docker itself failed to run the probe.
  docker run --rm --network bridge "$BUSYBOX_IMAGE" \
    ping -c 1 -W 2 "$INTERNAL_IP" >/dev/null 2>&1

  case $? in
    1) return 0 ;; # Correct: the default bridge cannot reach the internal network.
    0) return 1 ;; # Incorrect: the default bridge reached the internal network.
    *) return 2 ;; # Harness error, not proof of isolation.
  esac
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

printf 'Preparing Docker networking validation...\n'

if ! require_docker; then
  printf '❌ Docker daemon is not available to this user.\n' >&2
  exit 2
fi

print_environment

printf 'Checking test images...\n'
if ! ensure_image "$NGINX_IMAGE" || ! ensure_image "$BUSYBOX_IMAGE"; then
  printf '❌ Required test image could not be pulled or inspected.\n' >&2
  exit 2
fi

printf 'Creating temporary networks and containers...\n'
if ! docker network create --internal "$INTERNAL_NETWORK" >/dev/null 2>&1 ||
   ! docker network create "$FORWARDED_NETWORK" >/dev/null 2>&1 ||
   ! docker network create "$UNFORWARDED_NETWORK" >/dev/null 2>&1 ||
   ! docker network create "$SHARED_NETWORK" >/dev/null 2>&1 ||
   ! docker run -d --rm --name "$INTERNAL_WEB" \
       --network "$INTERNAL_NETWORK" "$NGINX_IMAGE" >/dev/null 2>&1 ||
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
  printf '❌ Could not create the temporary Docker test resources.\n' >&2
  exit 2
fi

INTERNAL_IP="$(
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
    "$INTERNAL_WEB"
)"

FORWARDED_BINDING="$(docker port "$FORWARDED_WEB" 80/tcp 2>/dev/null)"
FORWARDED_PORT="${FORWARDED_BINDING##*:}"

if [ -z "$INTERNAL_IP" ] ||
   [ -z "$FORWARDED_BINDING" ] ||
   [ "$FORWARDED_PORT" = "$FORWARDED_BINDING" ]; then
  printf '❌ Could not determine the temporary container IP or published port.\n' >&2
  exit 2
fi

wait_for_network_settle

printf 'Running connectivity checks...\n'
result \
  'Internal network is isolated from the default bridge' \
  internal_network_isolated

result \
  'Host namespace reaches a published container port' \
  host_reaches_published_port

result \
  'Unpublished container has no host-port mapping' \
  container_has_no_published_port

result \
  'Containers on the same bridge reach each other without published ports' \
  same_network_containers_reach_each_other

printf 'Cleaning up temporary test resources...\n'
cleanup
trap - EXIT

exit "$failures"

