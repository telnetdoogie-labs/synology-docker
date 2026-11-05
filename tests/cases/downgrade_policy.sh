#!/bin/bash
# Downgrades need explicit force; new engine enables setup steps. Run alone with: bash tests/run.sh downgrade_policy
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture

force='false'
docker_version='29.0.0'
target_docker_version='28.0.0'
skip_docker_update='false'
skip_compose_update='true'
skip_driver_update='true'
if (define_update) >/dev/null 2>&1; then
  printf 'Unintentional Docker downgrade unexpectedly succeeded\n' >&2
  exit 1
fi
force='true'
target_docker_explicit='true'
define_update

force='false'
skip_docker_update='true'
skip_compose_update='false'
compose_version='2.42.0'
target_compose_version='2.1.1'
if (define_update) >/dev/null 2>&1; then
  printf 'Unintentional Compose downgrade unexpectedly succeeded\n' >&2
  exit 1
fi
force='true'
skip_docker_update='false'
skip_compose_update='true'
target_docker_version='29.0.0'
install_iptables_modules='false'
install_apparmor='false'
skip_iptables_modules='false'
define_setup_steps
[[ "$install_iptables_modules" == 'true' && "$install_apparmor" == 'true' ]]
printf "Downgrade and force policy tests passed\n"
