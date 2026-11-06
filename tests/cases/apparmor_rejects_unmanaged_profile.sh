#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/apparmor_fixture.sh
source "$(dirname "$0")/../lib/apparmor_fixture.sh"

# Arrange: a user-owned profile already occupies the destination.
prepare_apparmor_fixture
printf 'unmanaged profile\n' > "$profile"

# Act/expect: refuse to overwrite an unmanaged profile or its parser.
expect_failure 'unmanaged profile prevents installation' bash "$apparmor_script"
expect_eq 'unmanaged profile' "$(<"$profile")" 'user-owned profile remains intact'
expect_files_equal /bin/true "$parser" 'failed install leaves original parser untouched'
