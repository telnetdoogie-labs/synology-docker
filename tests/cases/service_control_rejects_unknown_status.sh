#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture
force='true'

# Arrange: DSM 6/7 tools cannot determine the current service status.
cat > /usr/syno/bin/synopkg <<'EOF'
#!/bin/sh
printf 'unavailable\n'
EOF
cat > /usr/syno/sbin/synoservicectl <<'EOF'
#!/bin/sh
printf 'unavailable\n'
EOF
chmod +x /usr/syno/bin/synopkg /usr/syno/sbin/synoservicectl

# Act/expect: an unknown status is never treated as a safe stop.
for dsm_major_version in 6 7; do
  expect_failure "DSM $dsm_major_version rejects unknown service status" execute_stop_syno
done
