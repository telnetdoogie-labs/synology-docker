#!/bin/bash
# DSM 6 ships synoservicectl as root-only (0700). The probe usually runs without
# sudo, so it must still find the tool.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/dsm_runtime_fixture.sh
source "$(dirname "$0")/../lib/dsm_runtime_fixture.sh"

# Arrange: DSM 6 with a root-only synoservicectl, and a copy of the probe that an
# unprivileged user can read.
prepare_dsm_runtime_fixture
set_mock_dsm_version 6 6.2.4
chmod 0700 /usr/syno/sbin/synoservicectl
probe_copy_dir=$(mktemp -d)
trap 'rm -rf "$probe_copy_dir" "$test_tmp_dir"' EXIT
cp "$repo_dir/tests/check-dsm-runtime.sh" "$probe_copy_dir/"
chmod 0755 "$probe_copy_dir"
chmod 0644 "$probe_copy_dir/check-dsm-runtime.sh"

# Act: run the probe as an unprivileged user, as the README describes.
probe_output=$(runuser -u nobody -- sh "$probe_copy_dir/check-dsm-runtime.sh" 27 2>&1 || true)

# Expect: the root-only tool is still reported as present.
expect_contains "$probe_output" 'OK      DSM 6 synoservicectl found' 'root-only synoservicectl is found without sudo'
expect_not_contains "$probe_output" 'MISSING DSM 6 synoservicectl' 'no false missing report'
