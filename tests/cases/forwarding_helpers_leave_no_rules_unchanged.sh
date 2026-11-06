#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/forwarding_fixture.sh
source "$(dirname "$0")/../lib/forwarding_fixture.sh"

# Arrange: startup script has an anchor but no forwarding rules.
prepare_forwarding_fixture
cat > "$SYNO_DOCKER_SCRIPT" <<'EOF'
#!/bin/sh
$DockerUpdaterBin postdaemonup
EOF
forwarding_before=$(startup_script_hash)

# Act: switch forwarding mode when there is nothing to switch.
PATH="$iptables_bin:$PATH" bash "$repo_dir/switch_forward.sh" >/dev/null

# Expect: a no-op leaves the startup script unchanged.
expect_eq "$forwarding_before" "$(startup_script_hash)" 'switch with no forwarding rules leaves script untouched'
