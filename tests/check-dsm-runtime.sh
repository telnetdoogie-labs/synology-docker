#!/bin/sh
set -u

if [ "$#" -ne 1 ]; then
  printf 'Usage: sh %s TARGET_DOCKER_MAJOR\n' "$0" >&2
  exit 1
fi
case "$1" in
  ''|*[!0-9]*) printf 'Target Docker major version must be numeric\n' >&2; exit 1 ;;
esac
target_docker_major=$1
failed=0
check_command() {
  if command -v "$1" >/dev/null 2>&1; then
    printf 'OK      %s: %s\n' "$1" "$(command -v "$1")"
  else
    printf 'MISSING %s\n' "$1"
    failed=1
  fi
}

for tool in bash jq curl docker realpath readlink timeout mktemp comm sort awk sed tar find diff date; do
  check_command "$tool"
done

if [ -d /var/packages/ContainerManager ] || [ -d /var/packages/Docker ]; then
  printf 'OK      Synology Docker package directory found\n'
else
  printf 'MISSING Synology Docker package directory\n'
  failed=1
fi

dsm_major_version=$(awk -F= '$1 == "majorversion" { gsub(/"/, "", $2); print $2; exit }' /etc.defaults/VERSION 2>/dev/null)
printf 'DSM major version: %s\n' "${dsm_major_version:-unknown}"
case "$dsm_major_version" in
  6)
    if [ -x /usr/syno/sbin/synoservicectl ] || command -v synoservicectl >/dev/null 2>&1; then
      printf 'OK      DSM 6 synoservicectl found\n'
    else
      printf 'MISSING DSM 6 synoservicectl\n'
      failed=1
    fi
    ;;
  7)
    if [ -x /usr/syno/bin/synopkg ] || command -v synopkg >/dev/null 2>&1; then
      printf 'OK      DSM 7 synopkg found\n'
    else
      printf 'MISSING DSM 7 synopkg\n'
      failed=1
    fi
    ;;
  *)
    printf 'UNSUPPORTED DSM major version: %s (tests are scoped to DSM 6 and 7)\n' "${dsm_major_version:-unknown}"
    failed=1
    ;;
esac

if [ "$target_docker_major" -ge 28 ]; then
  for tool in insmod lsmod iptables sha256sum; do
    check_command "$tool"
  done
  if [ -x /bin/get_key_value ]; then
    printf 'OK      /bin/get_key_value found\n'
  else
    printf 'MISSING /bin/get_key_value (required for Docker Engine 28+)\n'
    failed=1
  fi
fi
if [ "$target_docker_major" -ge 29 ] && [ "$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)" = Y ]; then
  if [ -x /usr/sbin/apparmor_parser ] || [ -x /sbin/apparmor_parser ]; then
    printf 'OK      AppArmor parser found\n'
  else
    printf 'MISSING AppArmor parser (required for Docker Engine 29+)\n'
    failed=1
  fi
fi

if [ -x /bin/bash ] && /bin/bash -c 'values=(ok); [[ ${values[0]} == ok ]] && printf "%q" "two words" >/dev/null'; then
  printf 'OK      /bin/bash supports the script features in use\n'
else
  printf 'MISSING /bin/bash with arrays, [[ ]], and shell-quoting support\n'
  failed=1
fi

if command -v timeout >/dev/null 2>&1 && timeout --foreground 2 sh -c ':' >/dev/null 2>&1; then
  printf 'OK      timeout --foreground works\n'
else
  printf 'MISSING timeout --foreground support\n'
  failed=1
fi

if command -v readlink >/dev/null 2>&1 && readlink -f "$0" >/dev/null 2>&1; then
  printf 'OK      readlink -f works\n'
else
  printf 'MISSING readlink -f support\n'
  failed=1
fi

if command -v realpath >/dev/null 2>&1 && realpath "$0" >/dev/null 2>&1; then
  printf 'OK      realpath works\n'
else
  printf 'MISSING realpath support\n'
  failed=1
fi

if command -v mktemp >/dev/null 2>&1; then
  probe_dir=$(mktemp -d 2>/dev/null) || probe_dir=''
  if [ -n "$probe_dir" ] && [ -d "$probe_dir" ] && rmdir "$probe_dir"; then
    printf 'OK      mktemp -d works\n'
  else
    printf 'MISSING mktemp -d support\n'
    failed=1
  fi
else
  printf 'MISSING mktemp -d support\n'
  failed=1
fi

exit "$failed"
