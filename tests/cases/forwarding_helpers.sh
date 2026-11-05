#!/bin/bash
# Standalone forwarding helpers insert idempotently and fail safely. Run alone with: bash tests/run.sh forwarding_helpers
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture
prepare_installed_files

# Arrange: record iptables commands; fake a missing FORWARD jump.
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

# Act/expect: repeated runs insert forwarding rules once.
PATH="$iptables_bin:$PATH" bash "$repo_dir/fix_ipforward.sh" >/dev/null
PATH="$iptables_bin:$PATH" bash "$repo_dir/fix_ipforward.sh" >/dev/null
expect_file_occurrences "$SYNO_DOCKER_SCRIPT" 'iptables -P FORWARD ACCEPT' 1 'policy rule is inserted only once'
expect_file_occurrences "$SYNO_DOCKER_SCRIPT" 'iptables -C FORWARD -j DOCKER-FORWARD' 1 'forwarding check is inserted only once'
policy_line=$(grep -nF 'iptables -P FORWARD ACCEPT' "$SYNO_DOCKER_SCRIPT" | cut -d: -f1)
daemon_line=$(grep -nFx 'start_docker_daemon' "$SYNO_DOCKER_SCRIPT" | cut -d: -f1)
anchor_line=$(grep -nF "\$DockerUpdaterBin postdaemonup" "$SYNO_DOCKER_SCRIPT" | cut -d: -f1)
expect_success 'policy rule follows daemon start' test "$daemon_line" -lt "$policy_line"
expect_success 'policy rule precedes postdaemonup' test "$policy_line" -lt "$anchor_line"
expect_file_contains "$IPTABLES_LOG" '-P FORWARD ACCEPT' 'policy command was run'
expect_file_contains "$IPTABLES_LOG" '-I FORWARD 1 -j DOCKER-FORWARD' 'forwarding jump was run'

# Act/expect: switch forwarding modes, then switch back.
PATH="$iptables_bin:$PATH" bash "$repo_dir/switch_forward.sh" >/dev/null
expect_file_occurrences "$SYNO_DOCKER_SCRIPT" 'iptables -I FORWARD -i docker0 -j ACCEPT' 1 'docker0 input accept inserted'
expect_file_occurrences "$SYNO_DOCKER_SCRIPT" 'iptables -I FORWARD -o docker0 -j ACCEPT' 1 'docker0 output accept inserted'
expect_file_occurrences "$SYNO_DOCKER_SCRIPT" 'iptables -P FORWARD ACCEPT' 0 'policy rule removed when switching modes'
PATH="$iptables_bin:$PATH" bash "$repo_dir/switch_forward.sh" >/dev/null
expect_file_occurrences "$SYNO_DOCKER_SCRIPT" 'iptables -P FORWARD ACCEPT' 1 'policy rule restored on second switch'
expect_file_occurrences "$SYNO_DOCKER_SCRIPT" 'iptables -I FORWARD -i docker0 -j ACCEPT' 0 'docker0 rules removed on second switch'

# Arrange/expect: an anchor without forwarding rules needs no change.
cat > "$SYNO_DOCKER_SCRIPT" <<'EOF'
#!/bin/sh
$DockerUpdaterBin postdaemonup
EOF
forwarding_before=$(sha256sum "$SYNO_DOCKER_SCRIPT" | cut -d' ' -f1)
PATH="$iptables_bin:$PATH" bash "$repo_dir/switch_forward.sh" >/dev/null
expect_eq "$forwarding_before" "$(sha256sum "$SYNO_DOCKER_SCRIPT" | cut -d' ' -f1)" 'switch with no forwarding rules leaves script untouched'

# Arrange/expect: when rules exist but postdaemonup is missing, both helpers fail safely.
cat > "$SYNO_DOCKER_SCRIPT" <<'EOF'
#!/bin/sh
iptables -P FORWARD ACCEPT
EOF
forwarding_before=$(sha256sum "$SYNO_DOCKER_SCRIPT" | cut -d' ' -f1)
expect_failure 'fix helper rejects missing postdaemonup anchor' env PATH="$iptables_bin:$PATH" bash "$repo_dir/fix_ipforward.sh"
expect_eq "$forwarding_before" "$(sha256sum "$SYNO_DOCKER_SCRIPT" | cut -d' ' -f1)" 'failed fix leaves script untouched'
expect_failure 'switch helper rejects missing postdaemonup anchor' env PATH="$iptables_bin:$PATH" bash "$repo_dir/switch_forward.sh"
expect_eq "$forwarding_before" "$(sha256sum "$SYNO_DOCKER_SCRIPT" | cut -d' ' -f1)" 'failed switch leaves script untouched'
printf 'Standalone forwarding helper tests passed\n'
