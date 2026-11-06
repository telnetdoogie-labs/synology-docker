#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/kernel_modules_fixture.sh
source "$(dirname "$0")/../lib/kernel_modules_fixture.sh"

# Arrange: an empty module-loading section in the startup script.
prepare_kernel_modules_fixture
FILE="$test_tmp_dir/module-start.sh"
printf '# Load raw modules\n' > "$FILE"

# Act/expect: neither zero nor one module line suffices.
expect_failure 'startup script has no modules' start_script_loads_modules
printf 'insmod %s/%s\n' "$MODULES_FOLDER" "$IP4MODULE" >> "$FILE"
expect_failure 'startup script has only the IPv4 module' start_script_loads_modules

# Act/expect: both module lines satisfy the startup contract.
printf 'insmod %s/%s\n' "$MODULES_FOLDER" "$IP6MODULE" >> "$FILE"
expect_success 'startup script loads both modules' start_script_loads_modules >/dev/null
