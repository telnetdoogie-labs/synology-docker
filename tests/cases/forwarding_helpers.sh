#!/bin/bash
# Standalone forwarding helpers insert idempotently and fail safely. Run alone with: bash tests/run.sh forwarding_helpers
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
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
PATH="$iptables_bin:$PATH" bash "$repo_dir/fix_ipforward.sh" >/dev/null
PATH="$iptables_bin:$PATH" bash "$repo_dir/fix_ipforward.sh" >/dev/null
[[ $(grep -Fc 'iptables -P FORWARD ACCEPT' "$SYNO_DOCKER_SCRIPT") -eq 1 ]]
[[ $(grep -Fc 'iptables -C FORWARD -j DOCKER-FORWARD' "$SYNO_DOCKER_SCRIPT") -eq 1 ]]
policy_line=$(grep -nF 'iptables -P FORWARD ACCEPT' "$SYNO_DOCKER_SCRIPT" | cut -d: -f1)
daemon_line=$(grep -nFx 'start_docker_daemon' "$SYNO_DOCKER_SCRIPT" | cut -d: -f1)
anchor_line=$(grep -nF "\$DockerUpdaterBin postdaemonup" "$SYNO_DOCKER_SCRIPT" | cut -d: -f1)
[[ "$daemon_line" -lt "$policy_line" && "$policy_line" -lt "$anchor_line" ]]
grep -Fq -- '-P FORWARD ACCEPT' "$IPTABLES_LOG"
grep -Fq -- '-I FORWARD 1 -j DOCKER-FORWARD' "$IPTABLES_LOG"

PATH="$iptables_bin:$PATH" bash "$repo_dir/switch_forward.sh" >/dev/null
[[ $(grep -Fc 'iptables -I FORWARD -i docker0 -j ACCEPT' "$SYNO_DOCKER_SCRIPT") -eq 1 ]]
[[ $(grep -Fc 'iptables -I FORWARD -o docker0 -j ACCEPT' "$SYNO_DOCKER_SCRIPT") -eq 1 ]]
[[ $(grep -Fc 'iptables -P FORWARD ACCEPT' "$SYNO_DOCKER_SCRIPT") -eq 0 ]]
PATH="$iptables_bin:$PATH" bash "$repo_dir/switch_forward.sh" >/dev/null
[[ $(grep -Fc 'iptables -P FORWARD ACCEPT' "$SYNO_DOCKER_SCRIPT") -eq 1 ]]
[[ $(grep -Fc 'iptables -I FORWARD -i docker0 -j ACCEPT' "$SYNO_DOCKER_SCRIPT") -eq 0 ]]

cat > "$SYNO_DOCKER_SCRIPT" <<'EOF'
#!/bin/sh
$DockerUpdaterBin postdaemonup
EOF
forwarding_before=$(sha256sum "$SYNO_DOCKER_SCRIPT" | cut -d' ' -f1)
PATH="$iptables_bin:$PATH" bash "$repo_dir/switch_forward.sh" >/dev/null
[[ $(sha256sum "$SYNO_DOCKER_SCRIPT" | cut -d' ' -f1) == "$forwarding_before" ]]
cat > "$SYNO_DOCKER_SCRIPT" <<'EOF'
#!/bin/sh
iptables -P FORWARD ACCEPT
EOF
forwarding_before=$(sha256sum "$SYNO_DOCKER_SCRIPT" | cut -d' ' -f1)
if PATH="$iptables_bin:$PATH" bash "$repo_dir/fix_ipforward.sh" >/dev/null 2>&1; then
  printf 'Forwarding helper accepted a missing postdaemonup anchor\n' >&2
  exit 1
fi
[[ $(sha256sum "$SYNO_DOCKER_SCRIPT" | cut -d' ' -f1) == "$forwarding_before" ]]
if PATH="$iptables_bin:$PATH" bash "$repo_dir/switch_forward.sh" >/dev/null 2>&1; then
  printf 'Forwarding switch accepted a missing postdaemonup anchor\n' >&2
  exit 1
fi
[[ $(sha256sum "$SYNO_DOCKER_SCRIPT" | cut -d' ' -f1) == "$forwarding_before" ]]
printf 'Standalone forwarding helper tests passed\n'
