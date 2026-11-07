#!/bin/bash
# A module that doesn't match SHA256SUMS, or has no entry in it, is never installed.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/kernel_modules_fixture.sh
source "$(dirname "$0")/../lib/kernel_modules_fixture.sh"

# Arrange: the IPv4 module matches, but the IPv6 download differs from its checksum.
prepare_kernel_modules_fixture
MOCK_IP4_CONTENT='ip4 module'
MOCK_IP6_CONTENT='corrupted ip6 module'
MOCK_SUMS="$(module_checksum_line "$IP4MODULE" "$MOCK_IP4_CONTENT")
$(module_checksum_line "$IP6MODULE" 'ip6 module')
"
mock_module_downloads

# Act/expect: the mismatch fails the install, and neither module is placed.
expect_failure 'module with a mismatched checksum is rejected' download_and_place_modules
mismatch_output=$(download_and_place_modules 2>&1 || true)
expect_contains "$mismatch_output" "$IP6MODULE doesn't match its published checksum" 'mismatch names the module'
expect_contains "$mismatch_output" 'Run the script again' 'mismatch tells the user to retry'
expect_file_absent "$MODULES_FOLDER/$IP4MODULE" 'verified IPv4 module not installed alone'
expect_file_absent "$MODULES_FOLDER/$IP6MODULE" 'mismatched IPv6 module not installed'

# Arrange: SHA256SUMS lists only the IPv4 module.
MOCK_IP6_CONTENT='ip6 module'
MOCK_SUMS="$(module_checksum_line "$IP4MODULE" "$MOCK_IP4_CONTENT")
"

# Act/expect: a module with no published checksum can't be verified, so it's rejected.
expect_failure 'module without a published checksum is rejected' download_and_place_modules
missing_output=$(download_and_place_modules 2>&1 || true)
expect_contains "$missing_output" "No published checksum for $KERNEL_VERSION/$PLATFORM_VERSION/$IP6MODULE" \
  'missing entry names the module path'
expect_file_absent "$MODULES_FOLDER/$IP6MODULE" 'unverifiable IPv6 module not installed'

# Arrange: SHA256SUMS itself can't be downloaded.
SUMSDL='https://example.invalid/missing'

# Act/expect: without checksums, nothing is installed.
expect_failure 'missing SHA256SUMS is rejected' download_and_place_modules
expect_file_absent "$MODULES_FOLDER/$IP4MODULE" 'IPv4 module not installed without checksums'
