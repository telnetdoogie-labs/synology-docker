#!/bin/bash
# No kernel modules are published for DSM 6 kernels, so when they're missing DSM 6
# users are pointed at Docker 27, the newest Engine that doesn't need them.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/kernel_modules_fixture.sh
source "$(dirname "$0")/../lib/kernel_modules_fixture.sh"
prepare_kernel_modules_fixture

# Arrange: DSM 6 and DSM 7 version files.
dsm6_version="$test_tmp_dir/dsm6-VERSION"
dsm7_version="$test_tmp_dir/dsm7-VERSION"
printf 'majorversion="6"\nproductversion="6.2.4"\n' > "$dsm6_version"
printf 'majorversion="7"\nproductversion="7.2.2"\n' > "$dsm7_version"

# Act: explain the missing modules on each.
dsm6_output=$(explain_modules_unavailable "$dsm6_version")
dsm7_output=$(explain_modules_unavailable "$dsm7_version")

# Expect: DSM 6 is told about the Docker 27 limit and how to target it.
expect_contains "$dsm6_output" 'the newest Docker Engine DSM 6 can use is 27.x' 'DSM 6 is told about the Docker 27 limit'
expect_contains "$dsm6_output" '--docker 27.5.1' 'DSM 6 is shown how to target Docker 27'
expect_not_contains "$dsm6_output" 'compile them yourself' 'DSM 6 is not told to compile modules'

# Expect: DSM 7 keeps the advice to compile or request modules.
expect_contains "$dsm7_output" 'compile them yourself' 'DSM 7 keeps the compile advice'
expect_not_contains "$dsm7_output" 'DSM 6' 'DSM 7 gets no DSM 6 advice'

# Expect: both say the update can't continue.
expect_contains "$dsm6_output" 'We cannot continue without these modules.' 'DSM 6 says it cannot continue'
expect_contains "$dsm7_output" 'We cannot continue without these modules.' 'DSM 7 says it cannot continue'
