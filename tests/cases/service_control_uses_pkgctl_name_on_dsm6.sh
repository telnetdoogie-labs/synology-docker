#!/bin/bash
# DSM 6's synoservicectl only knows the package service as 'pkgctl-<package>'.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture
force='true'
dsm_major_version=6

# Arrange: a synoservicectl that behaves like DSM 6.2.4's. It rejects the bare
# package name and reports state in upstart's 'start/running' format.
service_state_file="$test_tmp_dir/service-state"
service_calls_file="$test_tmp_dir/service-calls"
echo running > "$service_state_file"
cat > /usr/syno/sbin/synoservicectl <<EOF
#!/bin/sh
echo "\$*" >> '$service_calls_file'
if [ "\$2" != 'pkgctl-$SYNO_DOCKER_SERV_NAME' ]; then
  echo "\$2 failed to get status... error unknow [0x4000 servicectl_status.c:27]"
  exit 255
fi
case "\$1" in
  --status)
    if [ "\$(cat '$service_state_file')" = running ]; then
      echo "\$2 start/running"
    else
      echo "\$2 stop/waiting"
    fi ;;
  --stop) echo stopped > '$service_state_file'; echo "\$2 stoped." ;;
  --start) echo running > '$service_state_file'; echo "\$2 started." ;;
esac
EOF
chmod +x /usr/syno/sbin/synoservicectl

# Act/expect: status is read from the pkgctl- service.
expect_eq started "$(get_syno_status)" 'DSM 6 status is read from the pkgctl- service'

# Act/expect: stopping and starting both go through the pkgctl- service.
execute_stop_syno >/dev/null
expect_eq stopped "$(get_syno_status)" 'DSM 6 service stops'
execute_start_syno >/dev/null
expect_eq false "$service_stopped" 'DSM 6 service start is recorded'
expect_file_contains "$service_calls_file" "--stop pkgctl-$SYNO_DOCKER_SERV_NAME" 'stop uses the pkgctl- name'
expect_file_contains "$service_calls_file" "--start pkgctl-$SYNO_DOCKER_SERV_NAME" 'start uses the pkgctl- name'
expect_eq 0 "$(grep -vc " pkgctl-$SYNO_DOCKER_SERV_NAME\$" "$service_calls_file" || true)" \
  'every synoservicectl call uses the pkgctl- name'

# Expect: commands printed for the user use the same name.
expect_eq "sudo synoservicectl --start pkgctl-$SYNO_DOCKER_SERV_NAME" "$(syno_start_cmd)" 'printed start command'
expect_eq "sudo synoservicectl --status pkgctl-$SYNO_DOCKER_SERV_NAME" "$(syno_status_cmd)" 'printed status command'
