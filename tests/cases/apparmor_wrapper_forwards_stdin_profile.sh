#!/bin/bash
# The installed AppArmor wrapper converts a stdin profile to a temporary file.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/apparmor_fixture.sh
source "$(dirname "$0")/../lib/apparmor_fixture.sh"

# Arrange: install the real wrapper in disposable paths, then substitute a
# recording implementation for the saved parser binary.
prepare_apparmor_fixture
install_managed_apparmor
export PARSER_RECORD="$test_tmp_dir/real-parser"
cat > "${parser}.real" <<'PARSER'
#!/bin/sh
printf '%s\n' "$@" > "${PARSER_RECORD}.args"
for arg in "$@"; do
  if [ -f "$arg" ]; then
    cp "$arg" "${PARSER_RECORD}.input"
  fi
done
PARSER
chmod +x "${parser}.real"

# Act: send a profile through stdin, with a parser option to preserve.
printf 'profile docker-default { file, }\n' | "$parser" -r

# Expect: the real parser receives the option and one temporary profile file.
expect_file_exists "${PARSER_RECORD}.input" 'stdin profile forwarded to real parser'
expect_file_contains "${PARSER_RECORD}.input" 'profile docker-default { file, }' 'stdin profile content preserved'
parser_args=$(<"${PARSER_RECORD}.args")
profile_path=${parser_args#*$'\n'}
expect_eq "-r" "${parser_args%%$'\n'*}" 'AppArmor parser option preserved'
expect_contains "$profile_path" '/tmp/apparmor_profile.' 'wrapper passes a temporary profile path'
expect_file_absent "$profile_path" 'temporary profile cleaned after parser completes'
