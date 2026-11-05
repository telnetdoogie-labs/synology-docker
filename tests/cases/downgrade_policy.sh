#!/bin/bash
# Downgrades need explicit force; new engine enables setup steps. Run alone with: bash tests/run.sh downgrade_policy
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture

# Arrange: the installed engine is newer than the target.
force='false'
docker_version='29.0.0'
target_docker_version='28.0.0'
skip_docker_update='false'
skip_compose_update='true'
skip_driver_update='true'
expect_failure 'engine downgrade needs explicit force' define_update

# Act/expect: explicit force permits the engine downgrade.
force='true'
target_docker_explicit='true'
define_update

force='false'

# Arrange/expect: Compose downgrade also requires force.
skip_docker_update='true'
skip_compose_update='false'
compose_version='2.42.0'
target_compose_version='2.1.1'
expect_failure 'Compose downgrade needs explicit force' define_update
force='true'
skip_docker_update='false'
skip_compose_update='true'

# Act/expect: an engine upgrade enables both setup steps.
target_docker_version='29.0.0'
install_iptables_modules='false'
install_apparmor='false'
skip_iptables_modules='false'
define_setup_steps
expect_eq true "$install_iptables_modules" 'engine upgrade enables iptables modules'
expect_eq true "$install_apparmor" 'engine upgrade enables AppArmor'
printf "Downgrade and force policy tests passed\n"
