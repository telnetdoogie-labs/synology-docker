#!/bin/bash
# DSM 6 and 7 service failures and starts. Run alone with: bash tests/run.sh service_control
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture

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
for dsm_major_version in 6 7; do
  if (execute_start_syno) >/dev/null 2>&1; then
    printf 'DSM %s failed service start was accepted\n' "$dsm_major_version" >&2
    exit 1
  fi
done
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
  [[ "$service_stopped" == 'false' ]]
done
printf '#!/bin/sh\nprintf "unavailable\\n"\n' > /usr/syno/bin/synopkg
printf '#!/bin/sh\nprintf "unavailable\\n"\n' > /usr/syno/sbin/synoservicectl
for dsm_major_version in 6 7; do
  if (execute_stop_syno) >/dev/null 2>&1; then
    printf 'DSM %s unknown service status was accepted\n' "$dsm_major_version" >&2
    exit 1
  fi
done
printf 'DSM 6/7 service failure tests passed\n'
