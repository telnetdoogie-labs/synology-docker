#!/bin/bash
# Update-script forwarding anchor and idempotency. Run alone with: bash tests/run.sh forwarding_preflight
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture
prepare_installed_files

printf '#!/bin/sh\n' > "$SYNO_DOCKER_SCRIPT"
skip_docker_update='true'
command='update'
validate_forwarding_anchor
execute_update_script >/dev/null
[[ $(wc -l < "$SYNO_DOCKER_SCRIPT") -eq 1 ]]
skip_docker_update='false'
command=''
if (execute_update_script) >/dev/null 2>&1; then
  printf 'Missing forwarding anchor was accepted\n' >&2
  exit 1
fi
[[ $(wc -l < "$SYNO_DOCKER_SCRIPT") -eq 1 ]]
cp "$repo_dir/test_file/start-stop-status" "$SYNO_DOCKER_SCRIPT"
execute_update_script >/dev/null
grep -q 'iptables -C FORWARD -j DOCKER-FORWARD' "$SYNO_DOCKER_SCRIPT"
execute_update_script >/dev/null
[[ $(grep -c 'iptables -C FORWARD -j DOCKER-FORWARD' "$SYNO_DOCKER_SCRIPT") -eq 1 ]]
printf 'Forwarding preflight and update tests passed\n'
