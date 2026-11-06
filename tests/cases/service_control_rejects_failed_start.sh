#!/bin/bash
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture
force='true'

# Arrange: DSM 6/7 service tools report a failed start.
cat > /usr/syno/bin/synopkg <<'EOF'
#!/bin/sh
if [ "$1" = status ]; then echo stopped; else exit 1; fi
EOF
cat > /usr/syno/sbin/synoservicectl <<'EOF'
#!/bin/sh
if [ "$1" = --status ]; then echo stopped; else exit 1; fi
EOF
chmod +x /usr/syno/bin/synopkg /usr/syno/sbin/synoservicectl
service_stopped='true'

# Act/expect: neither DSM version accepts a failed start.
for dsm_major_version in 6 7; do
  expect_failure "DSM $dsm_major_version rejects failed service start" execute_start_syno
done
