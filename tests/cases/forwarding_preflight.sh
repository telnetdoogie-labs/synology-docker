#!/bin/bash
# Update-script forwarding anchor and idempotency. Run alone with: bash tests/run.sh forwarding_preflight
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture
prepare_installed_files

# Arrange: the installed startup script lacks the forwarding anchor.
printf '#!/bin/sh\n' > "$SYNO_DOCKER_SCRIPT"
skip_docker_update='true'
command='update'
validate_forwarding_anchor
execute_update_script >/dev/null
expect_eq 1 "$(wc -l < "$SYNO_DOCKER_SCRIPT")" 'skip update leaves script unchanged'

# Act/expect: a full update must reject the missing anchor.
skip_docker_update='false'
command=''
expect_failure 'full update requires forwarding anchor' execute_update_script
expect_eq 1 "$(wc -l < "$SYNO_DOCKER_SCRIPT")" 'failed update leaves script unchanged'

# Act/expect: a valid script receives exactly one forwarding rule.
cp "$repo_dir/test_file/start-stop-status" "$SYNO_DOCKER_SCRIPT"
execute_update_script >/dev/null
expect_file_contains "$SYNO_DOCKER_SCRIPT" 'iptables -C FORWARD -j DOCKER-FORWARD' 'forwarding rule inserted'
execute_update_script >/dev/null
expect_eq 1 "$(grep -c 'iptables -C FORWARD -j DOCKER-FORWARD' "$SYNO_DOCKER_SCRIPT")" 'rule is inserted only once'
printf 'Forwarding preflight and update tests passed\n'
