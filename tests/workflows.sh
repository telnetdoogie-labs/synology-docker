#!/bin/bash
set -euo pipefail

if [[ "${DSM_MOCK_CONTAINER:-}" != '1' ]] || [[ "$(id -u)" -ne 0 ]]; then
  printf 'Run this test only inside the disposable Docker test image\n' >&2
  exit 1
fi

repo_dir=$(cd "$(dirname "$0")/.." && pwd -P)
test_tmp_dir=$(mktemp -d)
curl_args_file="$test_tmp_dir/curl-args"
trap 'rm -rf "$test_tmp_dir"' EXIT
mkdir -p /var/packages/ContainerManager/{target/usr/bin,etc,scripts} /usr/syno/{bin,sbin}
docker() { [[ "$1" = ps ]]; }
source "$repo_dir/syno_docker_update.sh"
cp "$repo_dir/test_file/dockerd.json" "$SYNO_DOCKER_JSON"

version_is_newer 100.0.0 29.9.9
version_is_newer 29.10.0 29.9.9
if version_is_newer 29.9.9 29.10.0 || version_is_newer 29.0.0 29.0.0; then
  printf 'Version comparison unexpectedly accepted a downgrade/equal version\n' >&2
  exit 1
fi
is_semver 29.1.0
if is_semver 29.1; then
  printf 'Invalid semver unexpectedly accepted\n' >&2
  exit 1
fi

if (curl() { return 22; }; target_docker_version=''; target_compose_version=''; detect_available_versions) >/dev/null 2>&1; then
  printf 'Docker lookup failure unexpectedly succeeded\n' >&2
  exit 1
fi
curl() {
  printf '%s\n' "$*" > "$curl_args_file"
  case "$2" in
    "${DOWNLOAD_DOCKER}/") printf '>docker-9.9.9.tgz\n>docker-29.9.9.tgz\n>docker-100.0.0.tgz\n' ;;
    "$GITHUB_API_COMPOSE") printf '{"tag_name":"v2.42.0"}\n' ;;
    *) return 22 ;;
  esac
}
target_docker_version=''
target_compose_version=''
detect_available_versions
[[ "$target_docker_version" == '100.0.0' ]]
[[ "$target_compose_version" == '2.42.0' ]]
curl_args=$(<"$curl_args_file")
[[ "$curl_args" == *"--proto =https"* ]]
[[ "$curl_args" == *"--proto-redir =https"* ]]
[[ "$curl_args" == *"--tlsv1.2"* ]]
unset -f curl

force='false'
docker_version='29.0.0'
target_docker_version='28.0.0'
skip_docker_update='false'
skip_compose_update='true'
skip_driver_update='true'
if (define_update) >/dev/null 2>&1; then
  printf 'Unintentional Docker downgrade unexpectedly succeeded\n' >&2
  exit 1
fi
force='true'
target_docker_explicit='true'
define_update

force='false'
skip_docker_update='true'
skip_compose_update='false'
compose_version='2.42.0'
target_compose_version='2.1.1'
if (define_update) >/dev/null 2>&1; then
  printf 'Unintentional Compose downgrade unexpectedly succeeded\n' >&2
  exit 1
fi
force='true'
skip_docker_update='false'
skip_compose_update='true'
target_docker_version='29.0.0'
install_iptables_modules='false'
install_apparmor='false'
skip_iptables_modules='false'
define_setup_steps
[[ "$install_iptables_modules" == 'true' && "$install_apparmor" == 'true' ]]
printf 'Version detection, downgrade, and force preparation tests passed\n'

mkdir -p "$test_tmp_dir/downloads"
: > "$test_tmp_dir/downloads/docker-28.0.0.tgz"
: > "$test_tmp_dir/downloads/docker-29.0.0.tgz"
download_dir="$test_tmp_dir/downloads"
target_docker_version=''
detect_available_downloads
[[ "$target_docker_version" == '29.0.0' ]]
docker_version='100.0.0'
force='false'
if (validate_offline_target) >/dev/null 2>&1; then
  printf 'Offline Docker downgrade unexpectedly succeeded\n' >&2
  exit 1
fi
force='true'
validate_offline_target
docker_version='29.0.0'
temp_dir=''
execute_prepare
[[ "$temp_dir" != "$download_dir" && -f "$download_dir/docker-29.0.0.tgz" ]]
execute_clean 'silent'
[[ -f "$download_dir/docker-29.0.0.tgz" ]]
printf 'Offline input and private temp directory tests passed\n'

for binary in docker dockerd docker-compose; do
  printf '#!/bin/sh\n' > "$SYNO_DOCKER_BIN/$binary"
done
cp "$repo_dir/test_file/dockerd.json" "$SYNO_DOCKER_JSON"
cp "$repo_dir/test_file/start-stop-status" "$SYNO_DOCKER_SCRIPT"
backup_dir="$test_tmp_dir"
docker_backup_filename='complete.tgz'
execute_backup >/dev/null
[[ -s "$backup_dir/$docker_backup_filename" ]]
[[ $(stat -c %a "$backup_dir/$docker_backup_filename") == 600 ]]
if (execute_backup) >/dev/null 2>&1; then
  printf 'Backup was overwritten\n' >&2
  exit 1
fi
rm "$SYNO_DOCKER_JSON"
docker_backup_filename='incomplete.tgz'
if (execute_backup) >/dev/null 2>&1; then
  printf 'Incomplete backup was accepted\n' >&2
  exit 1
fi
[[ ! -e "$backup_dir/$docker_backup_filename" ]]
cp "$repo_dir/test_file/dockerd.json" "$SYNO_DOCKER_JSON"
printf 'Backup validation tests passed\n'

docker_backup_filename='complete.tgz'
skip_docker_update='false'
skip_compose_update='false'
skip_driver_update='false'
stage='false'
temp_dir=$(mktemp -d)
execute_extract_backup >/dev/null
printf 'changed binary\n' > "$SYNO_DOCKER_BIN/docker"
execute_restore_bin >/dev/null
execute_restore_log >/dev/null
execute_restore_script >/dev/null
cmp -s "$temp_dir/docker/docker" "$SYNO_DOCKER_BIN/docker"
cmp -s "$temp_dir/dockerd.json" "$SYNO_DOCKER_JSON"
cmp -s "$temp_dir/start-stop-status" "$SYNO_DOCKER_SCRIPT"
cd "$repo_dir"
rm -rf "$temp_dir"
temp_dir=''
printf 'Backup extraction and successful restore tests passed\n'

temp_dir=$(mktemp -d)
mkdir -p "$temp_dir/docker"
cp "$SYNO_DOCKER_BIN/docker" "$temp_dir/docker/docker"
skip_docker_update='false'
skip_compose_update='true'
stage='false'
mv "$SYNO_DOCKER_BIN" "${SYNO_DOCKER_BIN}.saved"
: > "$SYNO_DOCKER_BIN"
if (execute_restore_bin) >/dev/null 2>&1; then
  printf 'Failed restore copy was accepted\n' >&2
  exit 1
fi
rm "$SYNO_DOCKER_BIN"
mv "${SYNO_DOCKER_BIN}.saved" "$SYNO_DOCKER_BIN"
rm -rf "$temp_dir"
temp_dir=''

printf '#!/bin/sh\n' > "$SYNO_DOCKER_SCRIPT"
skip_docker_update='true'
command='update'
validate_forwarding_anchor
execute_update_script >/dev/null
[[ $(wc -l < "$SYNO_DOCKER_SCRIPT") -eq 1 ]]
skip_docker_update='false'
command=''
if (execute_update_script) >/dev/null 2>&1; then
  printf 'Missing forwarding anchor was accepted\n' >&2
  exit 1
fi
[[ $(wc -l < "$SYNO_DOCKER_SCRIPT") -eq 1 ]]
cp "$repo_dir/test_file/start-stop-status" "$SYNO_DOCKER_SCRIPT"
execute_update_script >/dev/null
grep -q 'iptables -C FORWARD -j DOCKER-FORWARD' "$SYNO_DOCKER_SCRIPT"
execute_update_script >/dev/null
[[ $(grep -c 'iptables -C FORWARD -j DOCKER-FORWARD' "$SYNO_DOCKER_SCRIPT") -eq 1 ]]
printf 'Forwarding preflight and update tests passed\n'

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

source "$repo_dir/install_iptables_modules.sh"
USE_SYSTEMD='false'
KERNEL_VERSION='4.4.302+'
PLATFORM_VERSION=apollolake
MODULES_FOLDER="$test_tmp_dir/modules"
mkdir -p "$MODULES_FOLDER"
IP4MODULE=iptable_raw.ko
IP6MODULE=ip6table_raw.ko
IP4DL='https://example.invalid/ip4'
IP6DL='https://example.invalid/ip6'
curl() {
  printf '%s\n' "$*" > "$curl_args_file"
  local url='' destination=''
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -o) destination=$2; shift 2 ;;
      https:*) url=$1; shift ;;
      *) shift ;;
    esac
  done
  if [[ "$url" = "$IP4DL" ]]; then
    printf 'ip4\n' > "$destination"
  else
    printf 'ip6\n' > "$destination"
  fi
}
download_and_place_modules >/dev/null
curl_args=$(<"$curl_args_file")
[[ "$curl_args" == *"--proto =https"* ]]
[[ "$curl_args" == *"--proto-redir =https"* ]]
[[ "$curl_args" == *"--tlsv1.2"* ]]
[[ -f "$MODULES_FOLDER/$IP4MODULE" && -f "$MODULES_FOLDER/$IP6MODULE" ]]
curl() {
  return 1
}
if (download_and_place_modules) >/dev/null 2>&1; then
  printf 'Failed kernel module download was accepted\n' >&2
  exit 1
fi
unset -f curl
FILE="$test_tmp_dir/module-start.sh"
printf '# Load raw modules\n' > "$FILE"
if start_script_loads_modules >/dev/null; then
  printf 'Startup module check passed before modules were configured\n' >&2
  exit 1
fi
printf 'insmod %s/%s\n' "$MODULES_FOLDER" "$IP4MODULE" >> "$FILE"
if start_script_loads_modules >/dev/null; then
  printf 'Startup module check passed with only one module configured\n' >&2
  exit 1
fi
printf 'insmod %s/%s\n' "$MODULES_FOLDER" "$IP6MODULE" >> "$FILE"
start_script_loads_modules >/dev/null
printf 'Module download and startup checks passed\n'

parser="$test_tmp_dir/apparmor_parser"
enabled="$test_tmp_dir/apparmor-enabled"
profiles="$test_tmp_dir/apparmor-profiles"
apparmor_script="$test_tmp_dir/install_apparmor_profile.sh"
sed -e "s@/usr/sbin/apparmor_parser@$parser@g" -e "s@/sbin/apparmor_parser@$parser@g" \
  -e "s@/sys/module/apparmor/parameters/enabled@$enabled@g" \
  -e "s@/sys/kernel/security/apparmor/profiles@$profiles@g" \
  "$repo_dir/install_apparmor_profile.sh" > "$apparmor_script"
cp /bin/true "$parser"
printf 'Y\n' > "$enabled"
printf 'docker-default (enforce)\n' > "$profiles"
profile="/var/packages/ContainerManager/etc/docker-default.profile"
printf 'unmanaged profile\n' > "$profile"
if (bash "$apparmor_script") >/dev/null 2>&1; then
  printf 'Unmanaged AppArmor profile was overwritten\n' >&2
  exit 1
fi
cmp -s /bin/true "$parser"
rm "$profile"
(command bash "$apparmor_script") >/dev/null
[[ -f "$profile" && -f "${profile}.synology-docker-managed" && -x "${parser}.real" ]]
grep -q 'Synology DSM apparmor_parser wrapper' "$parser"
(command bash "$apparmor_script") >/dev/null
docker_backup_filename='apparmor-state.tgz'
execute_backup >/dev/null
tar -tzf "$test_tmp_dir/apparmor-state.tgz" | grep -q 'docker-default.profile.synology-docker-managed'
docker_backup_filename='complete.tgz'
temp_dir=$(mktemp -d)
execute_extract_backup >/dev/null
skip_docker_update='false'
bash() {
  if [[ "$1" = "${SCRIPT_DIR}/install_apparmor_profile.sh" ]]; then
    shift
    command bash "$apparmor_script" "$@"
  else
    command bash "$@"
  fi
}
execute_restore_script >/dev/null
[[ ! -e "$profile" && ! -e "${profile}.synology-docker-managed" && ! -e "${parser}.real" ]]
cd "$repo_dir"
rm -rf "$temp_dir"
temp_dir=''
docker_backup_filename='apparmor-state.tgz'
temp_dir=$(mktemp -d)
execute_extract_backup >/dev/null
execute_restore_script >/dev/null
unset -f bash
cmp -s "$temp_dir/docker-default.profile" "$profile"
[[ -f "${profile}.synology-docker-managed" && -x "${parser}.real" ]]
cd "$repo_dir"
rm -rf "$temp_dir"
temp_dir=''
bash "$apparmor_script" --restore >/dev/null
[[ ! -e "$profile" && ! -e "${profile}.synology-docker-managed" && ! -e "${parser}.real" ]]
cmp -s /bin/true "$parser"
if grep -q 'docker-default.profile' "$SYNO_DOCKER_SCRIPT"; then
  printf 'Unmanaged AppArmor profile entry remained in startup script\n' >&2
  exit 1
fi
: > "$profiles"
if (bash "$apparmor_script") >/dev/null 2>&1; then
  printf 'Failed AppArmor profile load was accepted\n' >&2
  exit 1
fi
[[ ! -e "$profile" && ! -e "${profile}.synology-docker-managed" && ! -e "${parser}.real" ]]
cmp -s /bin/true "$parser"
printf 'AppArmor install, rollback, and restore tests passed\n'

temp_dir=$(mktemp -d)
printf 'backup script\n' > "$temp_dir/start-stop-status"
skip_docker_update='true'
script_before=$(sha256sum "$SYNO_DOCKER_SCRIPT")
execute_restore_script >/dev/null
[[ $(sha256sum "$SYNO_DOCKER_SCRIPT") == "$script_before" ]]
rm -rf "$temp_dir"
temp_dir=''
printf 'Partial restore preserves the engine startup script\n'

mkdir -p "$test_tmp_dir/engine/docker" /etc.defaults
cp "$SYNO_DOCKER_BIN/docker" "$test_tmp_dir/engine/docker/docker"
cp "$SYNO_DOCKER_BIN/dockerd" "$test_tmp_dir/engine/docker/dockerd"
printf 'staged-only\n' >> "$test_tmp_dir/engine/docker/docker"
installed_docker_hash=$(sha256sum "$SYNO_DOCKER_BIN/docker" | cut -d' ' -f1)
installed_config_hash=$(sha256sum "$SYNO_DOCKER_JSON" | cut -d' ' -f1)
installed_script_hash=$(sha256sum "$SYNO_DOCKER_SCRIPT" | cut -d' ' -f1)
tar -czf "$test_tmp_dir/engine.tgz" -C "$test_tmp_dir/engine" docker
printf 'compose-binary\n' > "$test_tmp_dir/compose-binary"
printf 'majorversion="7"\nproductversion="7.2"\n' > /etc.defaults/VERSION
stage_output=$(
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
  download_dir=''
  temp_dir=''
  service_stopped='false'
  main --force --stage --path "$test_tmp_dir" --backup staged.tgz --docker 29.0.0 --compose 2.42.0 --target all update
)
stage_dir=$(printf '%s\n' "$stage_output" | sed -n 's/^Staged files: //p' | tail -n 1)
[[ -n "$stage_dir" && -f "$stage_dir/docker-29.0.0.tgz" && -f "$stage_dir/docker-compose" ]]
[[ -f "$stage_dir/docker/docker" && -f "$test_tmp_dir/staged.tgz" ]]
[[ $(sha256sum "$SYNO_DOCKER_BIN/docker" | cut -d' ' -f1) == "$installed_docker_hash" ]]
[[ $(sha256sum "$SYNO_DOCKER_JSON" | cut -d' ' -f1) == "$installed_config_hash" ]]
[[ $(sha256sum "$SYNO_DOCKER_SCRIPT" | cut -d' ' -f1) == "$installed_script_hash" ]]
rm -rf "$stage_dir"
printf 'Stage workflow retains its downloads without changing the installed binaries\n'

cp "$repo_dir/test_file/dockerd.json" "$SYNO_DOCKER_JSON"
cp "$repo_dir/test_file/start-stop-status" "$SYNO_DOCKER_SCRIPT"

logger_json="$test_tmp_dir/dockerd-switch.json"
cp "$repo_dir/test_file/dockerd.json" "$logger_json"
sh "$repo_dir/syno_docker_switch_logger.sh" "$logger_json" >/dev/null
[[ "$(jq -r '.["log-driver"]' "$logger_json")" == 'local' ]]
[[ "$(jq -r '.["log-opts"]["max-file"]' "$logger_json")" == '5' ]]
[[ "$(jq -r '.["log-opts"]["max-size"]' "$logger_json")" == '20m' ]]
[[ "$(jq -r '.["storage-driver"]' "$logger_json")" == 'btrfs' ]]
[[ "$(jq -r '.runtimes.nvidia.path' "$logger_json")" == '/usr/bin/nvidia-container-runtime' ]]
printf '{invalid\n' > "$logger_json"
if (sh "$repo_dir/syno_docker_switch_logger.sh" "$logger_json") >/dev/null 2>&1; then
  printf 'Invalid dockerd.json was accepted\n' >&2
  exit 1
fi
[[ "$(cat "$logger_json")" == '{invalid' ]]
if (sh "$repo_dir/syno_docker_switch_logger.sh" "$test_tmp_dir/missing.json") >/dev/null 2>&1; then
  printf 'Missing dockerd.json was accepted\n' >&2
  exit 1
fi
printf 'Logger switch tests passed\n'

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
[[ "$update_output" == *'Done.'* ]]
grep -q 'staged-only' "$SYNO_DOCKER_BIN/docker"
[[ "$(cat "$SYNO_DOCKER_BIN/docker-compose")" == 'compose-binary' ]]
[[ "$(jq -r '.["log-driver"]' "$SYNO_DOCKER_JSON")" == 'local' ]]
[[ "$(jq -r '.["log-opts"]["max-file"]' "$SYNO_DOCKER_JSON")" == '5' ]]
grep -q 'iptables -C FORWARD -j DOCKER-FORWARD' "$SYNO_DOCKER_SCRIPT"
[[ -f "$test_tmp_dir/update-apply.tgz" ]]
[[ "$(cat /tmp/synopkg-state)" == 'started' ]]
[[ -f "${profile}.synology-docker-managed" && -x "${parser}.real" ]]
[[ -z "$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'docker_update.*' -print -quit)" ]]
printf 'Non-stage update apply-path tests passed\n'

force='false'
skip_docker_update='false'
skip_compose_update='true'
skip_driver_update='false'
confirm_output=$(confirm_operation <<'EOF'
retry
YES
EOF
)
[[ "$confirm_output" == *'Please answer y(es) or n(o)'* ]]
[[ "$confirm_output" == *'Docker Engine'* ]]
[[ "$confirm_output" != *'Docker Compose'* ]]
confirm_sentinel="$test_tmp_dir/confirm-aborted"
(
  confirm_operation <<'EOF'
n
EOF
  : > "$confirm_sentinel"
)
[[ ! -e "$confirm_sentinel" ]]
force='true'
confirm_output=$(confirm_operation </dev/null)
[[ -z "$confirm_output" ]]
force='false'
printf 'Confirmation prompt tests passed\n'

skip_docker_update='false'
stage='false'
docker() { return 0; }
db_blocked_output=$(validate_db_logger 2>&1)
[[ -z "$db_blocked_output" ]]
docker() {
  if [[ "$1" = 'ps' && "${2:-}" = '-aq' ]]; then
    printf 'container-one\ncontainer-two\n'
    return 0
  fi
  if [[ "$1" = 'inspect' ]]; then
    case "$2" in
      container-one) printf '/container-one db\n' ;;
      container-two) printf '/container-two local\n' ;;
      *) return 1 ;;
    esac
    return 0
  fi
  return 1
}
if db_blocked_output=$(validate_db_logger 2>&1); then
  printf 'db-logger containers were not blocked\n' >&2
  exit 1
fi
[[ "$db_blocked_output" == *'container-one'* ]]
[[ "$db_blocked_output" != *'container-two'* ]]
[[ "$db_blocked_output" == *'--force'* ]]
[[ "$db_blocked_output" != *'http://'* && "$db_blocked_output" != *'https://'* ]]
force='true'
db_forced_output=$(validate_db_logger 2>&1)
[[ -z "$db_forced_output" ]]
force='false'
docker() {
  if [[ "$1" = 'ps' && "${2:-}" = '-aq' ]]; then
    printf 'container-one\n'
    return 0
  fi
  return 1
}
if (validate_db_logger) >/dev/null 2>&1; then
  printf 'db-logger inspection failure was not blocked\n' >&2
  exit 1
fi
skip_docker_update='true'
docker() { return 1; }
validate_db_logger
stage='true'
skip_docker_update='false'
validate_db_logger
stage='false'
docker() { [[ "$1" = ps ]]; }
printf 'db-logger preflight tests passed\n'

probe_bin="$test_tmp_dir/runtime-probe-bin"
mkdir -p "$probe_bin"
for tool in bash jq realpath readlink timeout mktemp awk; do
  tool_path=$(type -P "$tool" || true)
  [[ -n "$tool_path" ]] || { printf 'Required test utility missing: %s\n' "$tool" >&2; exit 1; }
  ln -s "$tool_path" "$probe_bin/$tool"
done
for tool in comm sort sed tar find diff date curl docker insmod lsmod iptables sha256sum; do
  tool_path=$(type -P "$tool" || true)
  if [[ -n "$tool_path" ]]; then
    ln -s "$tool_path" "$probe_bin/$tool"
  else
    printf '#!/bin/sh\nexit 0\n' > "$probe_bin/$tool"
    chmod +x "$probe_bin/$tool"
  fi
done
cat > /usr/syno/bin/synopkg <<'EOF'
#!/bin/sh
exit 0
EOF
cat > /usr/syno/sbin/synoservicectl <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x /usr/syno/bin/synopkg /usr/syno/sbin/synoservicectl
mkdir -p /etc.defaults
printf 'majorversion="7"\nproductversion="7.2"\n' > /etc.defaults/VERSION
probe_output=$(PATH="$probe_bin:$PATH" sh "$repo_dir/tests/check-dsm-runtime.sh" 27)
[[ "$probe_output" == *'DSM major version: 7'* ]]
[[ "$probe_output" == *'OK      DSM 7 synopkg found'* ]]
[[ "$probe_output" == *'OK      timeout --foreground works'* ]]
[[ "$probe_output" == *'OK      readlink -f works'* ]]
[[ "$probe_output" == *'OK      realpath works'* ]]
printf 'majorversion="6"\nproductversion="6.2"\n' > /etc.defaults/VERSION
probe_output=$(PATH="$probe_bin:$PATH" sh "$repo_dir/tests/check-dsm-runtime.sh" 27)
[[ "$probe_output" == *'OK      DSM 6 synoservicectl found'* ]]
printf 'majorversion="8"\nproductversion="8.0"\n' > /etc.defaults/VERSION
if probe_output=$(PATH="$probe_bin:$PATH" sh "$repo_dir/tests/check-dsm-runtime.sh" 27 2>&1); then
  printf 'Unsupported DSM version passed the runtime probe\n' >&2
  exit 1
fi
[[ "$probe_output" == *'UNSUPPORTED DSM major version: 8'* ]]
if probe_output=$(PATH="$probe_bin:$PATH" sh "$repo_dir/tests/check-dsm-runtime.sh" invalid 2>&1); then
  printf 'Non-numeric Docker major version passed the runtime probe\n' >&2
  exit 1
fi
[[ "$probe_output" == *'Target Docker major version must be numeric'* ]]
printf 'majorversion="7"\nproductversion="7.2"\n' > /etc.defaults/VERSION
if [[ ! -x /bin/get_key_value ]]; then
  if probe_output=$(PATH="$probe_bin:$PATH" sh "$repo_dir/tests/check-dsm-runtime.sh" 28 2>&1); then
    printf 'Docker 28 runtime probe passed without /bin/get_key_value\n' >&2
    exit 1
  fi
  [[ "$probe_output" == *'MISSING /bin/get_key_value'* ]]
fi
printf 'DSM runtime probe tests passed\n'

iptables_bin="$test_tmp_dir/iptables-bin"
mkdir -p "$iptables_bin"
cat > "$iptables_bin/iptables" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$IPTABLES_LOG"
case "$*" in
  *'-C FORWARD -j DOCKER-FORWARD'*) exit 1 ;;
esac
exit 0
EOF
chmod +x "$iptables_bin/iptables"
export IPTABLES_LOG="$test_tmp_dir/iptables.log"
: > "$IPTABLES_LOG"
cat > "$SYNO_DOCKER_SCRIPT" <<'EOF'
#!/bin/sh
$DockerUpdaterBin predaemonup
start_docker_daemon
$DockerUpdaterBin postdaemonup
EOF
PATH="$iptables_bin:$PATH" bash "$repo_dir/fix_ipforward.sh" >/dev/null
PATH="$iptables_bin:$PATH" bash "$repo_dir/fix_ipforward.sh" >/dev/null
[[ $(grep -Fc 'iptables -P FORWARD ACCEPT' "$SYNO_DOCKER_SCRIPT") -eq 1 ]]
[[ $(grep -Fc 'iptables -C FORWARD -j DOCKER-FORWARD' "$SYNO_DOCKER_SCRIPT") -eq 1 ]]
policy_line=$(grep -nF 'iptables -P FORWARD ACCEPT' "$SYNO_DOCKER_SCRIPT" | cut -d: -f1)
daemon_line=$(grep -nFx 'start_docker_daemon' "$SYNO_DOCKER_SCRIPT" | cut -d: -f1)
anchor_line=$(grep -nF "\$DockerUpdaterBin postdaemonup" "$SYNO_DOCKER_SCRIPT" | cut -d: -f1)
[[ "$daemon_line" -lt "$policy_line" && "$policy_line" -lt "$anchor_line" ]]
grep -Fq -- '-P FORWARD ACCEPT' "$IPTABLES_LOG"
grep -Fq -- '-I FORWARD 1 -j DOCKER-FORWARD' "$IPTABLES_LOG"

PATH="$iptables_bin:$PATH" bash "$repo_dir/switch_forward.sh" >/dev/null
[[ $(grep -Fc 'iptables -I FORWARD -i docker0 -j ACCEPT' "$SYNO_DOCKER_SCRIPT") -eq 1 ]]
[[ $(grep -Fc 'iptables -I FORWARD -o docker0 -j ACCEPT' "$SYNO_DOCKER_SCRIPT") -eq 1 ]]
[[ $(grep -Fc 'iptables -P FORWARD ACCEPT' "$SYNO_DOCKER_SCRIPT") -eq 0 ]]
PATH="$iptables_bin:$PATH" bash "$repo_dir/switch_forward.sh" >/dev/null
[[ $(grep -Fc 'iptables -P FORWARD ACCEPT' "$SYNO_DOCKER_SCRIPT") -eq 1 ]]
[[ $(grep -Fc 'iptables -I FORWARD -i docker0 -j ACCEPT' "$SYNO_DOCKER_SCRIPT") -eq 0 ]]

cat > "$SYNO_DOCKER_SCRIPT" <<'EOF'
#!/bin/sh
$DockerUpdaterBin postdaemonup
EOF
forwarding_before=$(sha256sum "$SYNO_DOCKER_SCRIPT" | cut -d' ' -f1)
PATH="$iptables_bin:$PATH" bash "$repo_dir/switch_forward.sh" >/dev/null
[[ $(sha256sum "$SYNO_DOCKER_SCRIPT" | cut -d' ' -f1) == "$forwarding_before" ]]
cat > "$SYNO_DOCKER_SCRIPT" <<'EOF'
#!/bin/sh
iptables -P FORWARD ACCEPT
EOF
forwarding_before=$(sha256sum "$SYNO_DOCKER_SCRIPT" | cut -d' ' -f1)
if PATH="$iptables_bin:$PATH" bash "$repo_dir/fix_ipforward.sh" >/dev/null 2>&1; then
  printf 'Forwarding helper accepted a missing postdaemonup anchor\n' >&2
  exit 1
fi
[[ $(sha256sum "$SYNO_DOCKER_SCRIPT" | cut -d' ' -f1) == "$forwarding_before" ]]
if PATH="$iptables_bin:$PATH" bash "$repo_dir/switch_forward.sh" >/dev/null 2>&1; then
  printf 'Forwarding switch accepted a missing postdaemonup anchor\n' >&2
  exit 1
fi
[[ $(sha256sum "$SYNO_DOCKER_SCRIPT" | cut -d' ' -f1) == "$forwarding_before" ]]
printf 'Standalone forwarding helper tests passed\n'

logging_dir="$test_tmp_dir/add-logging"
mkdir -p "$logging_dir/test_file"
cp "$repo_dir/test_file/start-stop-status.withlogging" "$logging_dir/test_file/start-stop-status.withlogging"
cp "$repo_dir/test_file/start-stop-status" "$SYNO_DOCKER_SCRIPT"
cp "$SYNO_DOCKER_SCRIPT" "$test_tmp_dir/start-stop-status.expected"
printf 'n\n' | (cd "$logging_dir" && bash "$repo_dir/add_logging_to_start_script.sh") >/dev/null
[[ ! -e "$logging_dir/start-stop-status.bkup" ]]
cmp -s "$test_tmp_dir/start-stop-status.expected" "$SYNO_DOCKER_SCRIPT"
printf 'YES\n' | (cd "$logging_dir" && bash "$repo_dir/add_logging_to_start_script.sh") >/dev/null
cmp -s "$test_tmp_dir/start-stop-status.expected" "$logging_dir/start-stop-status.bkup"
cmp -s "$repo_dir/test_file/start-stop-status.withlogging" "$SYNO_DOCKER_SCRIPT"
[[ $(stat -c '%a' "$SYNO_DOCKER_SCRIPT") == '744' ]]
printf 'Standalone logging helper tests passed\n'
