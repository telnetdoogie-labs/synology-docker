#!/bin/bash
# Lines pasted before the confirmation prompt appears must not be taken as its answer.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture

# Arrange: a script that asks for confirmation on a real terminal (via script(1)).
driver="$test_tmp_dir/confirm-driver.sh"
cat > "$driver" <<EOF
#!/bin/bash
source '$repo_dir/syno_docker_update.sh'
force=false skip_docker_update=false skip_compose_update=true skip_driver_update=true
confirm_operation
echo CONFIRMED
EOF

# Act: a line arrives straight away, as if pasted with the command, and the
# real answer is typed after the prompt has appeared.
terminal_output=$( (printf 'docker -v\n'; sleep 3; printf 'y\n') |
  script -qefc "bash '$driver'" /dev/null 2>&1 || true)

# Expect: the pasted line is ignored and reported, and only the typed answer counts.
expect_contains "$terminal_output" 'Ignored 1 line(s) typed or pasted before this prompt.' 'pasted line is reported'
expect_not_contains "$terminal_output" 'Please answer y(es) or n(o)' 'pasted line is not taken as an answer'
expect_contains "$terminal_output" 'CONFIRMED' 'answer typed after the prompt confirms'
