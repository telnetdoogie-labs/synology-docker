#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: an Engine 29 update has not enabled kernel or AppArmor setup.
init_update_fixture
skip_docker_update='false'
target_docker_version='29.0.0'
install_iptables_modules='false'
install_apparmor='false'
skip_iptables_modules='false'

# Act: calculate the version-dependent setup steps.
define_setup_steps

# Expect: Engine 29 enables both module and AppArmor preparation.
expect_eq true "$install_iptables_modules" 'engine upgrade enables iptables modules'
expect_eq true "$install_apparmor" 'engine upgrade enables AppArmor'
