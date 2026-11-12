#!/bin/bash
# Mock iptables, iptables-save and docker for syno_docker_forward_guard.sh cases.
# Source after test_env.sh. The guard runs under /bin/sh, as it does from DSM's startup script.
# shellcheck disable=SC2154,SC2034

prepare_forward_guard_fixture() {
  guard_bin="$test_tmp_dir/guard-bin"
  mkdir -p "$guard_bin"
  export IPTABLES_LOG="$test_tmp_dir/iptables.log"
  export IPTABLES_SAVE_OUTPUT="$test_tmp_dir/iptables-save.txt"
  export DOCKER_EVENTS_MODE=exit
  export DOCKER_EVENTS_PID="$test_tmp_dir/docker-events.pid"
  export SYNO_DOCKER_GUARD_PID_FILE="$test_tmp_dir/guard.pid"
  export SYNO_DOCKER_GUARD_DOCKER="$guard_bin/docker"
  export SYNO_DOCKER_GUARD_INTERVAL=1
  : > "$IPTABLES_LOG"

  cat > "$guard_bin/iptables" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$IPTABLES_LOG"
EOF
  cat > "$guard_bin/iptables-save" <<'EOF'
#!/bin/sh
cat "$IPTABLES_SAVE_OUTPUT"
EOF
  # 'events' blocks while dockerd is "up" (DOCKER_EVENTS_MODE=block) or returns at once when it has stopped.
  cat > "$guard_bin/docker" <<'EOF'
#!/bin/sh
case "$1" in
  events)
    [ "$DOCKER_EVENTS_MODE" = block ] || exit 1
    echo "$$" > "$DOCKER_EVENTS_PID"
    exec sleep 300 ;;
  version) exit 1 ;;
esac
exit 1
EOF
  chmod +x "$guard_bin/iptables" "$guard_bin/iptables-save" "$guard_bin/docker"
}

# Writes an iptables-save filter table: DSM's FORWARD_FIREWALL jump, Docker's chains, then the given FORWARD rules.
write_filter_table() {
  {
    printf '*filter\n:INPUT ACCEPT [0:0]\n:FORWARD ACCEPT [0:0]\n:OUTPUT ACCEPT [0:0]\n'
    printf ':DOCKER - [0:0]\n:DOCKER-FORWARD - [0:0]\n:DOCKER-USER - [0:0]\n:FORWARD_FIREWALL - [0:0]\n'
    printf '%s\n' "$@"
    printf -- '-A DOCKER-FORWARD -j DOCKER-CT\nCOMMIT\n'
  } > "$IPTABLES_SAVE_OUTPUT"
}

run_guard_once() {
  PATH="$guard_bin:$PATH" sh "$repo_dir/syno_docker_forward_guard.sh" --once
}
