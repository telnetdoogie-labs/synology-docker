#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/forwarding_fixture.sh
source "$(dirname "$0")/../lib/forwarding_fixture.sh"

# Arrange: startup script contains a forwarding rule but lacks postdaemonup.
prepare_forwarding_fixture
cat > "$SYNO_DOCKER_SCRIPT" <<'EOF'
#!/bin/sh
iptables -P FORWARD ACCEPT
EOF
forwarding_before=$(startup_script_hash)

# Act/expect: neither helper edits a script it cannot anchor safely.
expect_failure 'fix helper rejects missing postdaemonup anchor' env PATH="$iptables_bin:$PATH" bash "$repo_dir/fix_ipforward.sh"
expect_eq "$forwarding_before" "$(startup_script_hash)" 'failed fix leaves script untouched'
expect_failure 'switch helper rejects missing postdaemonup anchor' env PATH="$iptables_bin:$PATH" bash "$repo_dir/switch_forward.sh"
expect_eq "$forwarding_before" "$(startup_script_hash)" 'failed switch leaves script untouched'
