#!/bin/bash
# Mocked end-to-end apply updates installed files and service state. Run alone with: bash tests/run.sh apply_update
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
init_update_fixture
prepare_installed_files

# Arrange: fake AppArmor, downloads, DSM service state, and installed files.
parser="$test_tmp_dir/apparmor_parser"
enabled="$test_tmp_dir/apparmor-enabled"
profiles="$test_tmp_dir/apparmor-profiles"
apparmor_script="$test_tmp_dir/install_apparmor_profile.sh"
profile="/var/packages/ContainerManager/etc/docker-default.profile"
sed -e "s@/usr/sbin/apparmor_parser@$parser@g" -e "s@/sbin/apparmor_parser@$parser@g" \
  -e "s@/sys/module/apparmor/parameters/enabled@$enabled@g" \
  -e "s@/sys/kernel/security/apparmor/profiles@$profiles@g" \
  "$repo_dir/install_apparmor_profile.sh" > "$apparmor_script"
cp /bin/true "$parser"
printf 'Y\n' > "$enabled"
printf 'docker-default (enforce)\n' > "$profiles"
mkdir -p "$test_tmp_dir/engine/docker" /etc.defaults
cp "$SYNO_DOCKER_BIN/docker" "$test_tmp_dir/engine/docker/docker"
cp "$SYNO_DOCKER_BIN/dockerd" "$test_tmp_dir/engine/docker/dockerd"
printf 'staged-only\n' >> "$test_tmp_dir/engine/docker/docker"
tar -czf "$test_tmp_dir/engine.tgz" -C "$test_tmp_dir/engine" docker
printf 'compose-binary\n' > "$test_tmp_dir/compose-binary"
printf 'majorversion="7"\nproductversion="7.2"\n' > /etc.defaults/VERSION

cat > /usr/syno/bin/synopkg <<'EOF'
#!/bin/sh
state=/tmp/synopkg-state
[ -f "$state" ] || echo started > "$state"
case "$1" in
  status) cat "$state" ;;
  stop) echo stopped > "$state" ;;
  start) echo started > "$state" ;;
  *) exit 1 ;;
esac
EOF
chmod +x /usr/syno/bin/synopkg
rm -f /tmp/synopkg-state
printf 'docker-default (enforce)\n' > "$profiles"
printf 'Y\n' > "$enabled"

# Act: apply an update through the real entrypoint with mocked externals.
update_output=$(
  docker() {
    case "$1" in
      ps) return 0 ;;
      -v) printf 'Docker version 28.0.0, build test\n' ;;
      *) return 1 ;;
    esac
  }
  docker-compose() { printf 'Docker Compose version v2.1.1\n'; }
  containerd() { printf 'containerd containerd.io v1.7.0\n'; }
  runc() { printf 'runc version 1.1.0\n'; }
  curl() {
    local url='' destination=''
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        -o) destination=$2; shift 2 ;;
        https:*) url=$1; shift ;;
        *) shift ;;
      esac
    done
    case "$url" in
      "$DOWNLOAD_DOCKER/docker-29.0.0.tgz") cp "$test_tmp_dir/engine.tgz" "$destination" ;;
      */docker-compose-linux-x86_64) cp "$test_tmp_dir/compose-binary" "$destination" ;;
      *) return 22 ;;
    esac
    printf 200
  }
  bash() {
    if [[ "$1" = "${SCRIPT_DIR}/install_apparmor_profile.sh" ]]; then
      shift
      command bash "$apparmor_script" "$@"
    else
      command bash "$@"
    fi
  }
  download_dir=''
  temp_dir=''
  service_stopped='false'
  stage='false'
  command=''
  target='all'
  skip_docker_update='false'
  skip_compose_update='false'
  skip_driver_update='false'
  skip_iptables_modules='false'
  install_iptables_modules='false'
  install_apparmor='false'
  backup_filename_flag='false'
  main --force --skip-iptables --path "$test_tmp_dir" --backup update-apply.tgz \
    --docker 29.0.0 --compose 2.42.0 update
)

# Expect: new binaries/config/service state, backup, and no temp work.
expect_contains "$update_output" 'Done.' 'update reports completion'
expect_file_contains "$SYNO_DOCKER_BIN/docker" staged-only 'new engine binary is installed'
expect_eq compose-binary "$(<"$SYNO_DOCKER_BIN/docker-compose")" 'new Compose binary is installed'
expect_eq local "$(jq -r '.["log-driver"]' "$SYNO_DOCKER_JSON")" 'daemon uses local logging'
expect_eq 5 "$(jq -r '.["log-opts"]["max-file"]' "$SYNO_DOCKER_JSON")" 'daemon retains five log files'
expect_file_contains "$SYNO_DOCKER_SCRIPT" 'iptables -C FORWARD -j DOCKER-FORWARD' 'startup script includes forwarding rule'
expect_file_exists "$test_tmp_dir/update-apply.tgz" 'update saves a backup'
expect_eq started "$(</tmp/synopkg-state)" 'Container Manager is restarted'
expect_file_exists "${profile}.synology-docker-managed" 'managed AppArmor profile exists'
expect_success 'parser wrapper is executable' test -x "${parser}.real"
expect_eq '' "$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'docker_update.*' -print -quit)" 'temporary update directory was removed'
printf 'Non-stage update apply-path tests passed\n'
