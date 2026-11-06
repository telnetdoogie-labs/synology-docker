#!/bin/bash
# Mock iptables and the startup script for standalone forwarding-helper cases.
# Source after test_env.sh, which provides the guarded fake DSM filesystem.
# shellcheck disable=SC2154,SC2034

prepare_forwarding_fixture() {
  init_update_fixture
  prepare_installed_files

  iptables_bin="$test_tmp_dir/iptables-bin"
  mkdir -p "$iptables_bin"
  cat > "$iptables_bin/iptables" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$IPTABLES_LOG"
case "$*" in
  *'-C FORWARD -j DOCKER-FORWARD'*) exit 1 ;;
esac
exit 0
EOF
  chmod +x "$iptables_bin/iptables"
  export IPTABLES_LOG="$test_tmp_dir/iptables.log"
  : > "$IPTABLES_LOG"

  cat > "$SYNO_DOCKER_SCRIPT" <<'EOF'
#!/bin/sh
$DockerUpdaterBin predaemonup
start_docker_daemon
$DockerUpdaterBin postdaemonup
EOF
}

startup_script_hash() {
  sha256sum "$SYNO_DOCKER_SCRIPT" | cut -d' ' -f1
}
