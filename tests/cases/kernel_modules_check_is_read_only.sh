#!/bin/bash
# The pre-flight check (install_iptables_modules.sh --check) only reports whether the modules can be obtained;
# it never downloads or places them.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/kernel_modules_fixture.sh
source "$(dirname "$0")/../lib/kernel_modules_fixture.sh"
prepare_kernel_modules_fixture

# Arrange: answer availability lookups with $MOCK_HTTP_CODE and log every call.
curl_log="$test_tmp_dir/curl.log"
: > "$curl_log"
# shellcheck disable=SC2329 # Called by modules_available_for_download.
curl() {
  printf '%s\n' "$*" >> "$curl_log"
  printf '%s' "$MOCK_HTTP_CODE"
}

# Act and expect: modules already in place need no lookup.
touch "$MODULES_FOLDER/$IP4MODULE" "$MODULES_FOLDER/$IP6MODULE"
present_output=$(check_modules_obtainable)
expect_contains "$present_output" 'already in place' 'installed modules pass the check'
expect_eq '' "$(<"$curl_log")" 'installed modules are not looked up'
rm -f "$MODULES_FOLDER/$IP4MODULE" "$MODULES_FOLDER/$IP6MODULE"

# Act and expect: published modules pass without being downloaded.
MOCK_HTTP_CODE=200
available_output=$(check_modules_obtainable)
expect_contains "$available_output" 'available for download' 'published modules pass the check'
expect_eq 2 "$(grep -c -- '-o /dev/null' "$curl_log")" 'both modules are looked up without saving them'
expect_eq '' "$(find "$MODULES_FOLDER" -type f)" 'nothing is placed in the modules folder'

# Act and expect: missing modules fail the check with the usual explanation.
MOCK_HTTP_CODE=404
expect_failure 'missing modules fail the check' check_modules_obtainable
missing_output=$(check_modules_obtainable || true)
expect_contains "$missing_output" 'not available for download' 'missing modules are explained'
expect_eq '' "$(find "$MODULES_FOLDER" -type f)" 'a failed check places nothing'
