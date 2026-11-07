#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/kernel_modules_fixture.sh
source "$(dirname "$0")/../lib/kernel_modules_fixture.sh"

# Arrange: fake downloads whose checksums match, recording every curl call.
prepare_kernel_modules_fixture
MOCK_IP4_CONTENT='ip4 module'
MOCK_IP6_CONTENT='ip6 module'
MOCK_SUMS="$(module_checksum_line "$IP4MODULE" "$MOCK_IP4_CONTENT")
$(module_checksum_line "$IP6MODULE" "$MOCK_IP6_CONTENT")
"
mock_module_downloads
curl_calls_file="$test_tmp_dir/curl-calls"
MOCK_CURL_LOG=$curl_calls_file

# Act: download, verify, and place the IPv4 and IPv6 modules.
download_and_place_modules >/dev/null

# Expect: every download, including SHA256SUMS, is held to HTTPS and TLS 1.2.
expect_file_occurrences "$curl_calls_file" '--proto =https --proto-redir =https --tlsv1.2' 3 \
  'modules and checksums are all downloaded over HTTPS with TLS 1.2'
expect_file_contains "$curl_calls_file" "$SUMSDL" 'published checksums are downloaded'

# Expect: both verified modules are installed with their downloaded content.
expect_file_exists "$MODULES_FOLDER/$IP4MODULE" 'IPv4 module installed'
expect_file_exists "$MODULES_FOLDER/$IP6MODULE" 'IPv6 module installed'
expect_eq "$MOCK_IP4_CONTENT" "$(<"$MODULES_FOLDER/$IP4MODULE")" 'IPv4 module content preserved'
expect_eq "$MOCK_IP6_CONTENT" "$(<"$MODULES_FOLDER/$IP6MODULE")" 'IPv6 module content preserved'
