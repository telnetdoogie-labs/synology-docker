#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/forwarding_fixture.sh
source "$(dirname "$0")/../lib/forwarding_fixture.sh"

guard="/var/packages/ContainerManager/scripts/syno_docker_forward_guard.sh"
launch="/bin/sh $guard </dev/null >/dev/null 2>&1 &"

# Expect: the guard is installed, launched once, after the jump and before postdaemonup.
expect_guard_started_by_startup_script() {
  local source=$1 launch_line jump_line anchor_line
  expect_files_equal "$repo_dir/syno_docker_forward_guard.sh" "$guard" "$source installs the guard"
  expect_success "$source installs an executable guard" test -x "$guard"
  expect_file_occurrences "$SYNO_DOCKER_SCRIPT" "$launch" 1 "$source launches the guard once, in the background"
  launch_line=$(grep -nF "$launch" "$SYNO_DOCKER_SCRIPT" | cut -d: -f1)
  jump_line=$(grep -nF 'iptables -C FORWARD -j DOCKER-FORWARD' "$SYNO_DOCKER_SCRIPT" | cut -d: -f1)
  anchor_line=$(grep -nF "\$DockerUpdaterBin postdaemonup" "$SYNO_DOCKER_SCRIPT" | cut -d: -f1)
  expect_success "$source starts the guard after the jump" test "$jump_line" -lt "$launch_line"
  expect_success "$source starts the guard before postdaemonup" test "$launch_line" -lt "$anchor_line"
}

# Arrange/act: the updater rewrites the forwarding block twice.
prepare_forwarding_fixture
skip_docker_update='false'
command=''
execute_update_script >/dev/null
execute_update_script >/dev/null
expect_guard_started_by_startup_script 'updater'

# Arrange/act: from a fresh startup script and no guard, the standalone repair helper runs twice.
rm -f "$guard"
# shellcheck disable=SC2016 # Literal startup-script lines, not expansions.
printf '#!/bin/sh\n$DockerUpdaterBin predaemonup\nstart_docker_daemon\n$DockerUpdaterBin postdaemonup\n' > "$SYNO_DOCKER_SCRIPT"
PATH="$iptables_bin:$PATH" bash "$repo_dir/fix_ipforward.sh" >/dev/null
PATH="$iptables_bin:$PATH" bash "$repo_dir/fix_ipforward.sh" >/dev/null
expect_guard_started_by_startup_script 'fix_ipforward.sh'

# Act: switch to docker0 rules and back.
PATH="$iptables_bin:$PATH" bash "$repo_dir/switch_forward.sh" >/dev/null
expect_guard_started_by_startup_script 'switch_forward.sh (docker0 mode)'
PATH="$iptables_bin:$PATH" bash "$repo_dir/switch_forward.sh" >/dev/null
expect_guard_started_by_startup_script 'switch_forward.sh (policy mode)'
