#!/bin/bash
# Installs an apparmor_parser wrapper and docker-default profile for Docker >= 29.
#
# Docker >= 29.4.3 pipes its generated docker-default profile to apparmor_parser
# via stdin. Synology DSM's apparmor_parser (version 2.9, 2014-era) segfaults
# when reading from stdin:
#   "AppArmor enabled on system but the docker-default profile could not be
#    loaded: running '/sbin/apparmor_parser -Kr' failed with output: ...
#    error: signal: segmentation fault (core dumped)"
#
# In upstream Moby (daemon/daemon.go), dockerd unconditionally pipes its
# profile to apparmor_parser at startup regardless of whether docker-default
# was pre-loaded. Furthermore, on DSM 7 systemd manages dockerd directly
# (pkg-ContainerManager-dockerd.service), completely bypassing start-stop-status
# on boot and restarts.
#
# To permanently and reliably resolve this:
# 1. Install a transparent wrapper for /usr/sbin/apparmor_parser (saving the
#    original binary as .real). If invoked with stdin (no file arguments), the
#    wrapper buffers stdin to a temporary file and invokes the real parser with
#    that file, bypassing the stdin segfault bug.
# 2. Write and pre-load a compatible docker-default profile.
# 3. Add the pre-load hook to start-stop-status for DSM 6 compatibility.
#
# See https://github.com/moby/moby/issues/52785

PARSER="/usr/sbin/apparmor_parser"
if [ ! -e "$PARSER" ] && [ -e "/sbin/apparmor_parser" ]; then
  PARSER="/sbin/apparmor_parser"
fi

if [ -L "$PARSER" ]; then
  REAL_PATH=$(readlink -f "$PARSER" 2>/dev/null || readlink "$PARSER")
  if [ -n "$REAL_PATH" ] && [ -e "$REAL_PATH" ]; then
    PARSER="$REAL_PATH"
  fi
fi

REAL_PARSER="${PARSER}.real"

if [ -d "/var/packages/ContainerManager" ]; then
  PKG_DIR='/var/packages/ContainerManager'
elif [ -d "/var/packages/Docker" ]; then
  PKG_DIR='/var/packages/Docker'
else
  echo "Docker (or ContainerManager) folder was not found."
  exit 1
fi

PROFILE="${PKG_DIR}/etc/docker-default.profile"
SSS="${PKG_DIR}/scripts/start-stop-status"

# Handle restoration if called with --restore
if [ "$1" = "--restore" ]; then
  if [ -f "${REAL_PARSER}" ]; then
    mv -f "${REAL_PARSER}" "${PARSER}"
    echo " - restored original apparmor_parser binary"
  fi
  if [ -f "${PROFILE}" ]; then
    rm -f "${PROFILE}"
    echo " - removed ${PROFILE}"
  fi
  if [ -f "${SSS}" ]; then
    sed -i '/docker-default\.profile/d' "${SSS}"
    echo " - removed profile loading from start-stop-status"
  fi
  exit 0
fi

# No AppArmor on this system - nothing to do
if [ "$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)" != "Y" ]; then
  echo " - AppArmor not enabled on this system, skipping profile install."
  exit 0
fi

# 1. Install apparmor_parser wrapper
if [ -e "${PARSER}" ]; then
  if head -n 1 "${PARSER}" | grep -q '^#!'; then
    # Already a wrapper script
    if [ ! -f "${REAL_PARSER}" ]; then
      echo "ERROR: ${PARSER} is a script, but ${REAL_PARSER} does not exist."
      exit 1
    fi
    echo " - apparmor_parser wrapper already installed ? 🟢"
  else
    # Original ELF binary
    mv -f "${PARSER}" "${REAL_PARSER}" || {
      echo "ERROR: Could not back up ${PARSER} to ${REAL_PARSER}"
      exit 1
    }
    echo " - backed up original apparmor_parser to ${REAL_PARSER}"
  fi

  cat > "${PARSER}" << 'WRAPPER_EOF'
#!/bin/sh
# Synology DSM apparmor_parser wrapper to fix stdin segfault in version 2.9 (moby/moby#52785)
REAL_PARSER="/usr/sbin/apparmor_parser.real"
if [ ! -x "$REAL_PARSER" ]; then
  REAL_PARSER="/sbin/apparmor_parser.real"
fi

has_file=false
for arg in "$@"; do
  case "$arg" in
    -h|--help|-V|--version)
      exec "$REAL_PARSER" "$@"
      ;;
  esac
  if [ -f "$arg" ]; then
    has_file=true
    break
  fi
done

if [ "$has_file" = true ]; then
  exec "$REAL_PARSER" "$@"
fi

# No file specified in arguments -> reading from stdin
TMP_FILE=$(mktemp /tmp/apparmor_profile.XXXXXX)
if [ $? -ne 0 ] || [ -z "$TMP_FILE" ]; then
  exec "$REAL_PARSER" "$@"
fi

trap 'rm -f "$TMP_FILE"' EXIT HUP INT TERM

cat > "$TMP_FILE"
"$REAL_PARSER" "$@" "$TMP_FILE"
exit $?
WRAPPER_EOF

  chmod 755 "${PARSER}"
  echo " - apparmor_parser stdin wrapper installed ? 🟢"
else
  echo "WARNING: apparmor_parser binary not found at ${PARSER}"
fi

# 2. Write compatible docker-default profile
# Profile derived from moby's contrib/apparmor template, in syntax accepted by
# DSM's apparmor_parser 2.9 (no includes, no @{PROC} tunables, no ptrace/signal
# rules - not mediated on these kernels).
cat > "${PROFILE}" << 'PROFILE_EOF'
profile docker-default flags=(attach_disconnected,mediate_deleted) {
  network,
  capability,
  file,
  umount,

  deny /proc/* w,
  deny /proc/{[^1-9],[^1-9][^0-9],[^1-9s][^0-9y][^0-9s],[^1-9][^0-9][^0-9][^0-9]*}/** w,
  deny /proc/sys/[^k]** w,
  deny /proc/sys/kernel/{?,??,[^s][^h][^m]**} w,
  deny /proc/sysrq-trigger rwklx,
  deny /proc/kcore rwklx,
  deny /proc/kmem rwklx,
  deny /proc/mem rwklx,

  deny mount,

  deny /sys/[^f]*/** wklx,
  deny /sys/f[^s]*/** wklx,
  deny /sys/fs/[^c]*/** wklx,
  deny /sys/fs/c[^g]*/** wklx,
  deny /sys/fs/cg[^r]*/** wklx,
  deny /sys/firmware/** rwklx,
  deny /sys/kernel/security/** rwklx,
}
PROFILE_EOF

echo " - profile written to ${PROFILE}"

# Load it now (replace if already loaded)
if ! "${PARSER}" -Kr "${PROFILE}"; then
  echo "ERROR: ${PARSER} could not load ${PROFILE}"
  exit 1
fi
if ! grep -q 'docker-default' /sys/kernel/security/apparmor/profiles; then
  echo "ERROR: docker-default not present after load"
  exit 1
fi
echo " - docker-default profile loaded ? 🟢"

# 3. Load it at every ContainerManager start, before dockerd (DSM 6 / package starts).
if ! grep -q 'docker-default.profile' "${SSS}"; then
  INSERT="            # Added by docker update\n            [ -f \"${PROFILE}\" ] && ${PARSER} -Kr \"${PROFILE}\""
  match="^[[:space:]]*# start docker[[:space:]]*$"
  sed -i "/${match}/i\\${INSERT}" "${SSS}"
  if grep -q 'docker-default.profile' "${SSS}"; then
    echo " - CM script loads profile   ? 🟢"
  else
    echo "ERROR: could not add profile load to ${SSS} - anchor '# start docker' not found"
    exit 1
  fi
else
  echo " - CM script loads profile   ? 🟢 (already present)"
fi

exit 0
