#!/bin/bash
# Installs a docker-default AppArmor profile and configures ContainerManager to
# load it before dockerd starts.
#
# Docker >= 29.4.3 pipes its generated docker-default profile to apparmor_parser
# via stdin, which segfaults DSM's apparmor_parser (2.9, 2014-era). Containers
# then fail to start with:
#   "AppArmor enabled on system but the docker-default profile could not be
#    loaded: ... signal: segmentation fault"
# dockerd skips generating/loading the profile when one named docker-default is
# already loaded, so pre-loading a compatible profile avoids the crash entirely.
# See https://github.com/moby/moby/issues/52785

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

# No AppArmor on this system - nothing to do
if [ "$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)" != "Y" ]; then
  echo " - AppArmor not enabled on this system, skipping profile install."
  exit 0
fi

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
if ! /sbin/apparmor_parser -Kr "${PROFILE}"; then
  echo "ERROR: /sbin/apparmor_parser could not load ${PROFILE}"
  exit 1
fi
if ! grep -q 'docker-default' /sys/kernel/security/apparmor/profiles; then
  echo "ERROR: docker-default not present after load"
  exit 1
fi
echo " - docker-default profile loaded ? 🟢"

# Load it at every ContainerManager start, before dockerd. The profile is
# consumed by dockerd, so unlike the FORWARD rules this must run pre-daemon.
if ! grep -q 'docker-default.profile' "${SSS}"; then
  INSERT="            # Added by docker update\n            [ -f \"${PROFILE}\" ] && /sbin/apparmor_parser -Kr \"${PROFILE}\""
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
