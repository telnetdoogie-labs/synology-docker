#!/bin/bash
# DSM 7 uses a systemd drop-in for raw modules and retires legacy script hooks.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/kernel_modules_fixture.sh
source "$(dirname "$0")/../lib/kernel_modules_fixture.sh"

# Arrange: a DSM 7 startup script has both legacy module lines and a
# separate forwarding block that must survive the migration.
prepare_kernel_modules_fixture
USE_SYSTEMD='true'
DOCKERD_UNIT='pkg-ContainerManager-dockerd'
DROPIN_DIR="$test_tmp_dir/systemd"
DROPIN="$DROPIN_DIR/iptables-raw-modules.conf"
FILE="$test_tmp_dir/start-stop-status"
printf '%s\n' \
  '# Added by docker update' \
  '# Load raw modules' \
  'insmod /lib/modules/iptable_raw.ko' \
  'insmod /lib/modules/ip6table_raw.ko' \
  '# Added by docker update' \
  'iptables -P FORWARD ACCEPT' > "$FILE"
systemctl_calls="$test_tmp_dir/systemctl-calls"
systemctl() { printf '%s\n' "$*" >> "$systemctl_calls"; }

# Act: install the real module drop-in, then remove only the obsolete hooks.
modify_script >/dev/null
remove_script_insert >/dev/null

# Expect: the service loads both modules before Docker and reloads systemd.
expect_file_contains "$DROPIN" "insmod $MODULES_FOLDER/$IP4MODULE" 'drop-in loads IPv4 raw module'
expect_file_contains "$DROPIN" "insmod $MODULES_FOLDER/$IP6MODULE" 'drop-in loads IPv6 raw module'
expect_file_contains "$systemctl_calls" 'daemon-reload' 'systemd reloads after installing drop-in'
expect_eq true "$(start_script_loads_modules)" 'module startup checks the DSM 7 drop-in'

# Expect: only the legacy module hooks disappear; forwarding remains intact.
expect_file_lacks "$FILE" 'Load raw modules' 'legacy module block removed'
expect_file_lacks "$FILE" 'insmod /lib/modules/' 'legacy raw module commands removed'
expect_file_contains "$FILE" 'iptables -P FORWARD ACCEPT' 'forwarding configuration retained'
expect_file_occurrences "$FILE" '# Added by docker update' 1 'forwarding marker retained once'
