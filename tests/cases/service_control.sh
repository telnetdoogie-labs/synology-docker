#!/bin/bash
# DSM 6 and 7 service failures and starts. Run alone with: bash tests/run.sh service_control
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture

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
force='true'
service_stopped='true'

# Act/expect: neither DSM version accepts a failed start.
for dsm_major_version in 6 7; do
  expect_failure "DSM $dsm_major_version rejects failed service start" execute_start_syno
done

# Arrange: service tools now report successful starts.
cat > /usr/syno/bin/synopkg <<'EOF'
#!/bin/sh
if [ "$1" = status ]; then echo started; fi
EOF
cat > /usr/syno/sbin/synoservicectl <<'EOF'
#!/bin/sh
if [ "$1" = --status ]; then echo running; fi
EOF
for dsm_major_version in 6 7; do
  service_stopped='true'
  execute_start_syno >/dev/null
  expect_eq false "$service_stopped" "DSM $dsm_major_version records successful start"
done

# Arrange/expect: unknown service status must not be treated as stopped.
printf '#!/bin/sh\nprintf "unavailable\\n"\n' > /usr/syno/bin/synopkg
printf '#!/bin/sh\nprintf "unavailable\\n"\n' > /usr/syno/sbin/synoservicectl
for dsm_major_version in 6 7; do
  expect_failure "DSM $dsm_major_version rejects unknown service status" execute_stop_syno
done
printf 'DSM 6/7 service failure tests passed\n'
