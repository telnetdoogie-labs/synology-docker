#!/bin/bash
# Bind mounts with spaces stay one argv item and retain read-only mode.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/container_fixture.sh
source "$(dirname "$0")/../lib/container_fixture.sh"
# shellcheck source=tests/lib/recreate_hint_fixture.sh
source "$(dirname "$0")/../lib/recreate_hint_fixture.sh"

# Arrange: inspected container has a read-only bind and a writable named volume.
# Act: render the suggestion and replay it against fake Docker.
render_recreate_hint
printf -v quoted_volume '%q' "$malicious_source:/data path:ro"

# Expect: quoting protects the spaced path without losing :ro or volume identity.
expect_contains "$suggestion" "-v $quoted_volume" 'quotes the read-only bind mount'
expect_contains "$suggestion" '-v /var/lib/docker/volumes/config_volume/_data:/config' 'retains named volume'
expect_contains "$run_result" "<$malicious_source:/data path:ro>" 'passes read-only bind as one argument'
expect_contains "$run_result" '</var/lib/docker/volumes/config_volume/_data:/config>' 'passes named volume'
expect_file_absent "$test_tmp_dir/should-not-run-mount" 'bind path did not execute'
