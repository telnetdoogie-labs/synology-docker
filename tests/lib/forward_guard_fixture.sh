#!/bin/bash
# Mock iptables, ip6tables, their -save tools and docker for syno_docker_forward_guard.sh cases.
# Source after test_env.sh. The guard runs under /bin/sh, as it does from DSM's startup script.
# shellcheck disable=SC2154,SC2034

prepare_forward_guard_fixture() {
  guard_bin="$test_tmp_dir/guard-bin"
  mkdir -p "$guard_bin"
  export IPTABLES_LOG="$test_tmp_dir/iptables.log"
  export IP6TABLES_LOG="$test_tmp_dir/ip6tables.log"
  export IPTABLES_SAVE_OUTPUT="$test_tmp_dir/iptables-save.txt"
  export IP6TABLES_SAVE_OUTPUT="$test_tmp_dir/ip6tables-save.txt"
  export DOCKER_EVENTS_MODE=exit
  export DOCKER_EVENTS_PID="$test_tmp_dir/docker-events.pid"
  export SYNO_DOCKER_GUARD_CONF="$test_tmp_dir/guard.conf"
  export SYNO_DOCKER_GUARD_PID_FILE="$test_tmp_dir/guard.pid"
  export SYNO_DOCKER_GUARD_DOCKER="$guard_bin/docker"
  export SYNO_DOCKER_GUARD_INTERVAL=1
  : > "$IPTABLES_LOG"
  : > "$IP6TABLES_LOG"

  local tool log output
  for tool in iptables ip6tables; do
    log=IPTABLES_LOG
    output=IPTABLES_SAVE_OUTPUT
    if [ "$tool" = ip6tables ]; then
      log=IP6TABLES_LOG
      output=IP6TABLES_SAVE_OUTPUT
    fi
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$%s"\n' "$log" > "$guard_bin/$tool"
    # The Nth call prints <output>.N when that file exists (the table after a delete), else <output>.
    cat > "$guard_bin/$tool-save" <<EOF
#!/bin/sh
out=\$$output
calls=\$((\$(cat "\$out.calls" 2>/dev/null || echo 0) + 1))
echo "\$calls" > "\$out.calls"
if [ -f "\$out.\$calls" ]; then
  cat "\$out.\$calls"
elif [ -f "\$out" ]; then
  cat "\$out"
fi
EOF
    chmod +x "$guard_bin/$tool" "$guard_bin/$tool-save"
  done

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
  chmod +x "$guard_bin/docker"
}

# Writes an iptables-save filter table to a file: DSM's FORWARD_FIREWALL chain, Docker's chains, then the given FORWARD
# rules. Resets the -save call count for that table.
write_table() {
  local file=$1
  shift
  {
    printf '*filter\n:INPUT ACCEPT [0:0]\n:FORWARD ACCEPT [0:0]\n:OUTPUT ACCEPT [0:0]\n'
    printf ':DOCKER - [0:0]\n:DOCKER-FORWARD - [0:0]\n:DOCKER-USER - [0:0]\n:FORWARD_FIREWALL - [0:0]\n'
    printf '%s\n' "$@"
    printf -- '-A DOCKER-FORWARD -j DOCKER-CT\nCOMMIT\n'
  } > "$file"
  rm -f "${file%.[0-9]}.calls"
}

write_filter_table() {
  rm -f "$IPTABLES_SAVE_OUTPUT".[0-9]
  write_table "$IPTABLES_SAVE_OUTPUT" "$@"
  : > "$IPTABLES_LOG"
}

# The IPv4 table the second iptables-save call sees, after the guard has deleted misplaced jumps.
write_filter_table_after_delete() {
  write_table "$IPTABLES_SAVE_OUTPUT.2" "$@"
}

set_placement() {
  printf '%s\n' "$1" > "$SYNO_DOCKER_GUARD_CONF"
}

run_guard_once() {
  PATH="$guard_bin:$PATH" sh "$repo_dir/syno_docker_forward_guard.sh" --once
}
