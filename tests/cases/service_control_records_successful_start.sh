#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture
force='true'

# Arrange: DSM 6/7 service tools report a successful start.
cat > /usr/syno/bin/synopkg <<'EOF'
#!/bin/sh
if [ "$1" = status ]; then echo started; fi
EOF
cat > /usr/syno/sbin/synoservicectl <<'EOF'
#!/bin/sh
if [ "$1" = --status ]; then echo running; fi
EOF
chmod +x /usr/syno/bin/synopkg /usr/syno/sbin/synoservicectl

# Act/expect: each successful start clears the stopped flag.
for dsm_major_version in 6 7; do
  service_stopped='true'
  execute_start_syno >/dev/null
  expect_eq false "$service_stopped" "DSM $dsm_major_version records successful start"
done
