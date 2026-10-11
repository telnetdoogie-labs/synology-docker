#!/bin/bash
#======================================================================================================================
# Title         : install_fuse_overlayfs.sh
# Description   : Installs fuse-overlayfs support for Docker on Synology NAS
#                 Only for kernels without the overlay module (e.g., DSM 7 kernel 4.4.x) on volumes where Docker
#                 uses the 'aufs' storage driver. Volumes using 'btrfs' don't need this and are left alone.
# Usage         : sudo ./install_fuse_overlayfs.sh [--yes] [--uninstall]
# Credits       : Originally written by @doctorpangloss (AppMana/forks-synology-docker)
# Repository    : https://github.com/telnetdoogie-labs/synology-docker
#======================================================================================================================

set -e

readonly RED='\e[31m'
readonly NC='\e[m'
readonly BOLD='\e[1m'

terminate() {
  printf "${RED}${BOLD}%s${NC}\n" "ERROR: $1" >&2
  exit 1
}

usage() {
  echo "Usage: sudo $0 [--yes] [--uninstall]"
  echo
  echo "  --yes        Don't ask for confirmation before switching the storage driver"
  echo "  --uninstall  Undo the changes made by this script and restore the previous dockerd.json"
}

assume_yes='false'
action='install'
while [ "$1" != "" ]; do
  case "$1" in
    -y | --yes ) assume_yes='true' ;;
    --uninstall ) action='uninstall' ;;
    -h | --help ) usage; exit 0 ;;
    * ) usage; terminate "Unrecognized parameter ($1)" ;;
  esac
  shift
done

# Test if script has root privileges
if [ "$(id -u)" -ne 0 ]; then
  usage
  terminate "You need to be root to run this script"
fi

readonly CPU_ARCH='x86_64'
if [ "$(uname -m)" != "${CPU_ARCH}" ]; then
  terminate "This script supports ${CPU_ARCH} CPUs only"
fi

#======================================================================================================================
# Pinned downloads and their SHA-256 checksums (verified against each project's published checksums)
#======================================================================================================================
readonly FUSE_OVERLAYFS_SNAPSHOTTER_VERSION='2.1.7'
readonly FUSE_OVERLAYFS_VERSION='1.16'
readonly FUSE3_DEB_VERSION='3.14.0-4'

readonly FUSE_OVERLAYFS_GRPC_URL="https://github.com/containerd/fuse-overlayfs-snapshotter/releases/download/v${FUSE_OVERLAYFS_SNAPSHOTTER_VERSION}/containerd-fuse-overlayfs-${FUSE_OVERLAYFS_SNAPSHOTTER_VERSION}-linux-amd64.tar.gz"
readonly FUSE_OVERLAYFS_GRPC_SHA256='d54148043c22381af89cec2a167431e40668716404a1eb682ca69dfb890376f3'
readonly FUSE_OVERLAYFS_URL="https://github.com/containers/fuse-overlayfs/releases/download/v${FUSE_OVERLAYFS_VERSION}/fuse-overlayfs-${CPU_ARCH}"
readonly FUSE_OVERLAYFS_SHA256='30c6b9e192600d6854e13397974c709d7cabd980b7d1a4d67defd8eb69677e91'
readonly FUSE3_DEB_URL="https://deb.debian.org/debian/pool/main/f/fuse3/fuse3_${FUSE3_DEB_VERSION}_amd64.deb"
readonly FUSE3_DEB_SHA256='63b97d9b9acf9e8346ba59e87aa36a47205f05050808f8e9087dca603fd07ab8'
readonly LIBFUSE3_DEB_URL="https://deb.debian.org/debian/pool/main/f/fuse3/libfuse3-3_${FUSE3_DEB_VERSION}_amd64.deb"
readonly LIBFUSE3_DEB_SHA256='bf535cec5e965823fd03199b4029f9e9f3952111eb12824b5d2b96c8cca1a918'

#======================================================================================================================
# Paths
#======================================================================================================================
if [ -d "/var/packages/ContainerManager" ]; then
  readonly SYNO_DOCKER_DIR='/var/packages/ContainerManager'
  readonly SYNO_DOCKER_SERV_NAME='ContainerManager'
elif [ -d "/var/packages/Docker" ]; then
  readonly SYNO_DOCKER_DIR='/var/packages/Docker'
  readonly SYNO_DOCKER_SERV_NAME='Docker'
else
  terminate "Docker (or ContainerManager) folder was not found."
fi

readonly SYNO_DOCKER_JSON="${SYNO_DOCKER_DIR}/etc/dockerd.json"
readonly SYNO_DOCKER_JSON_BACKUP="${SYNO_DOCKER_JSON}.pre-fuse-overlayfs"
readonly CONTAINERD_BIN="${SYNO_DOCKER_DIR}/target/usr/bin/containerd"
readonly SYNO_UPDATER="${SYNO_DOCKER_DIR}/target/tool/updater"
DOCKER_DATA_ROOT=$(jq -r --arg d "${SYNO_DOCKER_DIR}/var/docker" '.["data-root"] // $d' "${SYNO_DOCKER_JSON}" 2>/dev/null) \
  || DOCKER_DATA_ROOT="${SYNO_DOCKER_DIR}/var/docker"
readonly DOCKER_DATA_ROOT
readonly RC_SCRIPT='/usr/local/etc/rc.d/containerd-fuse-overlayfs.sh'
readonly LEGACY_FUSE_OVERLAYFS_DATA='/volume1/@docker/containerd-fuse-overlayfs'

# Keep the snapshot data where an earlier install put it (AppMana's fork used a fixed /volume1 path), otherwise images
# and containers stored under fuse-overlayfs would disappear
FUSE_OVERLAYFS_DATA=$(sed -n 's/^FUSE_OVERLAYFS_DATA="\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' "${RC_SCRIPT}" 2>/dev/null | head -1)
if [ -z "${FUSE_OVERLAYFS_DATA}" ]; then
  if [ -d "${LEGACY_FUSE_OVERLAYFS_DATA}" ]; then
    FUSE_OVERLAYFS_DATA="${LEGACY_FUSE_OVERLAYFS_DATA}"
  else
    FUSE_OVERLAYFS_DATA="${DOCKER_DATA_ROOT}/containerd-fuse-overlayfs"
  fi
fi
readonly FUSE_OVERLAYFS_DATA

readonly CONTAINERD_CONFIG='/etc/containerd/config.toml'
readonly CONFIG_MARKER='# Managed by install_fuse_overlayfs.sh'
readonly SYSTEMD_DROPIN_DIR="/etc/systemd/system/pkg-${SYNO_DOCKER_SERV_NAME}-dockerd.service.d"
readonly SYSTEMD_DROPIN="${SYSTEMD_DROPIN_DIR}/no-iptables-raw.conf"

#======================================================================================================================
# Downloads a file and verifies its SHA-256 checksum, terminating on any failure.
#======================================================================================================================
# Arguments:
#   $1 - URL
#   $2 - Output file
#   $3 - Expected SHA-256
#======================================================================================================================
fetch() {
  curl -fsSL --retry 3 -o "$2" "$1" || terminate "Download failed: $1"
  echo "$3  $2" | sha256sum -c - >/dev/null 2>&1 || terminate "Checksum mismatch for $1"
}

#======================================================================================================================
# Check if fuse module is available
#======================================================================================================================
check_fuse_support() {
  echo "Checking FUSE support..."
  if [ ! -e /dev/fuse ]; then
    modprobe fuse 2>/dev/null || true
    if [ ! -e /dev/fuse ]; then
      terminate "FUSE is not available (/dev/fuse missing). Cannot proceed."
    fi
  fi
  echo "  FUSE support: OK"
}

#======================================================================================================================
# Exits if the kernel supports overlay natively (built in or as a module), as fuse-overlayfs isn't needed then.
#======================================================================================================================
check_overlay_needed() {
  modprobe overlay 2>/dev/null || true
  if grep -qw overlay /proc/filesystems; then
    echo "Native overlay support is available, so fuse-overlayfs is not needed on this system. Nothing to do."
    exit 0
  fi
  echo "  Native overlay support: not available (fuse-overlayfs needed)"
}

#======================================================================================================================
# Only switch the storage driver away from 'aufs' (unusable on Docker 24+). Any other driver, notably Synology's
# default 'btrfs', works without overlay, and switching would hide every existing image and container.
#======================================================================================================================
check_storage_driver() {
  current_driver=$(jq -r '.["storage-driver"] // empty' "${SYNO_DOCKER_JSON}")
  case "${current_driver}" in
    fuse-overlayfs )
      echo "  Storage driver: already fuse-overlayfs, refreshing the installation"
      ;;
    aufs | "" )
      echo "  Storage driver: ${current_driver:-not set} -> fuse-overlayfs"
      echo
      echo "WARNING: Images and containers created with the current storage driver will not be visible after the"
      echo "         switch. You will need to pull images and recreate containers (volumes and bind mounts are kept)."
      echo "         To undo, run: sudo $0 --uninstall"
      if [ "${assume_yes}" != 'true' ]; then
        printf "Switch Docker to fuse-overlayfs? [y/N] "
        read -r response
        case "${response}" in
          y | Y | yes ) ;;
          * ) echo "Aborted."; exit 1 ;;
        esac
      fi
      ;;
    * )
      terminate "Docker uses the '${current_driver}' storage driver, which doesn't need overlay. fuse-overlayfs is only for setups on 'aufs'; switching would hide all existing images and containers."
      ;;
  esac
}

#======================================================================================================================
# Install fuse-overlayfs binary
#======================================================================================================================
install_fuse_overlayfs() {
  echo "Installing fuse-overlayfs v${FUSE_OVERLAYFS_VERSION}..."
  if [ -f /usr/local/bin/fuse-overlayfs ]; then
    echo "  Already installed, skipping"
  else
    fetch "${FUSE_OVERLAYFS_URL}" "${work_dir}/fuse-overlayfs" "${FUSE_OVERLAYFS_SHA256}"
    install -m 755 "${work_dir}/fuse-overlayfs" /usr/local/bin/fuse-overlayfs
    echo "  Installed to /usr/local/bin/fuse-overlayfs"
  fi
}

#======================================================================================================================
# Install fuse3 userspace tools (fusermount3, mount.fuse3, libfuse3)
#======================================================================================================================
install_fuse3_tools() {
  echo "Installing fuse3 userspace tools..."
  if [ -f /usr/local/bin/fusermount3 ] && [ -f /sbin/mount.fuse3 ] && [ -e /usr/lib/libfuse3.so.3 ]; then
    echo "  Already installed, skipping"
    return
  fi

  local deb_dir="${work_dir}/fuse3"
  mkdir -p "${deb_dir}"
  fetch "${FUSE3_DEB_URL}" "${deb_dir}/fuse3.deb" "${FUSE3_DEB_SHA256}"
  fetch "${LIBFUSE3_DEB_URL}" "${deb_dir}/libfuse3.deb" "${LIBFUSE3_DEB_SHA256}"
  for deb in fuse3 libfuse3; do
    (cd "${deb_dir}" && ar x "${deb}.deb" && tar xf data.tar.* && rm -f data.tar.* control.tar.* debian-binary)
  done

  install -m 755 "${deb_dir}/bin/fusermount3" /usr/local/bin/fusermount3
  install -m 755 "${deb_dir}/sbin/mount.fuse3" /sbin/mount.fuse3

  # Keep DSM's own libfuse3 if it ships one
  if [ -e /usr/lib/libfuse3.so.3 ]; then
    echo "  Installed fusermount3, mount.fuse3 (using the existing libfuse3)"
    return
  fi
  local libfile
  libfile=$(find "${deb_dir}/lib/x86_64-linux-gnu" -name 'libfuse3.so.3.*' -type f | head -1)
  [ -n "${libfile}" ] || terminate "libfuse3 not found in the downloaded package"
  install -m 644 "${libfile}" "/usr/lib/$(basename "${libfile}")"
  ln -s "/usr/lib/$(basename "${libfile}")" /usr/lib/libfuse3.so.3
  ldconfig 2>/dev/null || true
  echo "  Installed fusermount3, mount.fuse3, libfuse3"
}

#======================================================================================================================
# Install containerd-fuse-overlayfs-grpc binary
#======================================================================================================================
install_grpc_snapshotter() {
  echo "Installing containerd-fuse-overlayfs-grpc v${FUSE_OVERLAYFS_SNAPSHOTTER_VERSION}..."
  if [ -f /usr/local/bin/containerd-fuse-overlayfs-grpc ]; then
    echo "  Already installed, skipping"
  else
    fetch "${FUSE_OVERLAYFS_GRPC_URL}" "${work_dir}/grpc.tar.gz" "${FUSE_OVERLAYFS_GRPC_SHA256}"
    tar xzf "${work_dir}/grpc.tar.gz" -C "${work_dir}" containerd-fuse-overlayfs-grpc
    install -m 755 "${work_dir}/containerd-fuse-overlayfs-grpc" /usr/local/bin/containerd-fuse-overlayfs-grpc
    echo "  Installed to /usr/local/bin/containerd-fuse-overlayfs-grpc"
  fi
}

#======================================================================================================================
# Create containerd config with fuse-overlayfs proxy plugin
#======================================================================================================================
create_containerd_config() {
  echo "Creating containerd config..."
  mkdir -p "$(dirname "${CONTAINERD_CONFIG}")"
  if [ -f "${CONTAINERD_CONFIG}" ] && ! grep -qF "${CONFIG_MARKER}" "${CONTAINERD_CONFIG}" && \
    ! grep -qF 'proxy_plugins."fuse-overlayfs"' "${CONTAINERD_CONFIG}"; then
    cp "${CONTAINERD_CONFIG}" "${CONTAINERD_CONFIG}.pre-fuse-overlayfs"
    echo "  Backed up existing config to ${CONTAINERD_CONFIG}.pre-fuse-overlayfs"
  fi
  cat > "${CONTAINERD_CONFIG}" <<TOML
${CONFIG_MARKER}
version = 2
root = "${DOCKER_DATA_ROOT}/containerd/daemon"
state = "/run/containerd"
disabled_plugins = ["io.containerd.grpc.v1.cri"]

[grpc]
  address = "/run/containerd/containerd.sock"

[proxy_plugins]
  [proxy_plugins."fuse-overlayfs"]
    type = "snapshot"
    address = "/run/containerd/fuse-overlayfs.sock"
TOML
  echo "  Created ${CONTAINERD_CONFIG}"
}

#======================================================================================================================
# Create rc.d startup script (runs at boot, before the Docker package starts)
#======================================================================================================================
create_startup_script() {
  echo "Creating startup script..."
  mkdir -p "$(dirname "${RC_SCRIPT}")"
  cat > "${RC_SCRIPT}" <<RCEOF
#!/bin/sh
# Start containerd-fuse-overlayfs-grpc and external containerd before Docker
# Required for Docker on Synology kernels without the overlay module
# Created by install_fuse_overlayfs.sh (remove with: install_fuse_overlayfs.sh --uninstall)

FUSE_OVERLAYFS_GRPC=/usr/local/bin/containerd-fuse-overlayfs-grpc
FUSE_OVERLAYFS_SOCK=/run/containerd/fuse-overlayfs.sock
FUSE_OVERLAYFS_DATA="${FUSE_OVERLAYFS_DATA}"
CONTAINERD="${CONTAINERD_BIN}"
CONTAINERD_CONFIG="${CONTAINERD_CONFIG}"
CONTAINERD_SOCK=/run/containerd/containerd.sock

case "\$1" in
  start)
    mkdir -p /run/containerd "\$FUSE_OVERLAYFS_DATA"

    # Start fuse-overlayfs grpc daemon
    if [ ! -S "\$FUSE_OVERLAYFS_SOCK" ]; then
      nohup "\$FUSE_OVERLAYFS_GRPC" "\$FUSE_OVERLAYFS_SOCK" "\$FUSE_OVERLAYFS_DATA" \\
        > /var/log/containerd-fuse-overlayfs.log 2>&1 &
      sleep 1
    fi

    # Start external containerd
    if [ ! -S "\$CONTAINERD_SOCK" ]; then
      nohup "\$CONTAINERD" --config "\$CONTAINERD_CONFIG" \\
        > /var/log/containerd.log 2>&1 &
      sleep 2
    fi
    ;;
  stop)
    pkill -f "containerd --config \$CONTAINERD_CONFIG" 2>/dev/null
    pkill containerd-fuse-overlayfs-grpc 2>/dev/null
    rm -f "\$FUSE_OVERLAYFS_SOCK" "\$CONTAINERD_SOCK"
    ;;
  *)
    echo "Usage: \$0 {start|stop}"
    exit 1
    ;;
esac
RCEOF
  chmod 755 "${RC_SCRIPT}"
  echo "  Created ${RC_SCRIPT}"
}

#======================================================================================================================
# Configure dockerd.json for fuse-overlayfs, keeping a copy of the original for --uninstall
#======================================================================================================================
configure_dockerd() {
  echo "Configuring dockerd.json..."
  # An install from an earlier version (or AppMana's fork) left no backup, and the current file is already the
  # fuse-overlayfs one, so it isn't worth keeping as "the original"
  if [ ! -f "${SYNO_DOCKER_JSON_BACKUP}" ] && \
    [ "$(jq -r '.["storage-driver"] // empty' "${SYNO_DOCKER_JSON}")" != 'fuse-overlayfs' ]; then
    cp "${SYNO_DOCKER_JSON}" "${SYNO_DOCKER_JSON_BACKUP}"
    echo "  Backed up original to ${SYNO_DOCKER_JSON_BACKUP}"
  fi
  local tmpfile="${SYNO_DOCKER_JSON}.tmp"
  jq '. + {"containerd": "/run/containerd/containerd.sock", "storage-driver": "fuse-overlayfs"}' \
    "${SYNO_DOCKER_JSON}" > "${tmpfile}" && mv "${tmpfile}" "${SYNO_DOCKER_JSON}"
  echo "  Updated ${SYNO_DOCKER_JSON}"
}

#======================================================================================================================
# Neutralize Synology updater that re-injects storage-driver: aufs
#======================================================================================================================
neutralize_updater() {
  echo "Neutralizing Synology updater..."
  if [ -f "${SYNO_UPDATER}" ] && [ ! -f "${SYNO_UPDATER}.orig" ]; then
    cp -p "${SYNO_UPDATER}" "${SYNO_UPDATER}.orig"
    printf '#!/bin/sh\n# Disabled by install_fuse_overlayfs.sh (original: updater.orig)\nexit 0\n' > "${SYNO_UPDATER}"
    chmod 755 "${SYNO_UPDATER}"
    echo "  Replaced updater with no-op (original backed up)"
  else
    echo "  Already neutralized or not present"
  fi
}

#======================================================================================================================
# Kernel 4.4 can also lack iptable_raw. Only when it can't be loaded, tell dockerd to run without it via a systemd
# drop-in; this relaxes Docker's raw-table protection, so it isn't applied where the module is available.
#======================================================================================================================
configure_iptables_raw() {
  if lsmod | grep -q '^iptable_raw' || modprobe iptable_raw 2>/dev/null || \
    { [ -f /lib/modules/iptable_raw.ko ] && insmod /lib/modules/iptable_raw.ko 2>/dev/null; }; then
    echo "iptable_raw is available, no iptables workaround needed"
    rm -f "${SYSTEMD_DROPIN}"
    return
  fi
  echo "iptable_raw is not available, creating systemd drop-in to run dockerd without it..."
  mkdir -p "${SYSTEMD_DROPIN_DIR}"
  printf '[Service]\nEnvironment="DOCKER_INSECURE_NO_IPTABLES_RAW=1"\n' > "${SYSTEMD_DROPIN}"
  systemctl daemon-reload
  echo "  Created ${SYSTEMD_DROPIN}"
}

#======================================================================================================================
# Undo the changes made by this script
#======================================================================================================================
uninstall() {
  echo "=== Removing fuse-overlayfs support ==="
  [ -x "${RC_SCRIPT}" ] && "${RC_SCRIPT}" stop || true
  rm -f "${RC_SCRIPT}"
  if [ -f "${SYNO_DOCKER_JSON_BACKUP}" ]; then
    mv "${SYNO_DOCKER_JSON_BACKUP}" "${SYNO_DOCKER_JSON}"
    echo "  Restored ${SYNO_DOCKER_JSON}"
  elif [ "$(jq -r '.["storage-driver"] // empty' "${SYNO_DOCKER_JSON}")" = 'fuse-overlayfs' ]; then
    # Installed without a backup (an earlier version or AppMana's fork): remove the fuse-overlayfs settings
    local tmpfile="${SYNO_DOCKER_JSON}.tmp"
    jq 'del(.["storage-driver"], .["containerd"])' "${SYNO_DOCKER_JSON}" > "${tmpfile}" && \
      mv "${tmpfile}" "${SYNO_DOCKER_JSON}"
    echo "  Removed the fuse-overlayfs settings from ${SYNO_DOCKER_JSON} (no backup of the original was found)."
    echo "  Check \"storage-driver\" before restarting; Synology's updater sets it again on the next start."
  fi
  if [ -f "${SYNO_UPDATER}.orig" ]; then
    mv "${SYNO_UPDATER}.orig" "${SYNO_UPDATER}"
    echo "  Restored Synology updater"
  fi
  if [ -f "${CONTAINERD_CONFIG}" ] && { grep -qF "${CONFIG_MARKER}" "${CONTAINERD_CONFIG}" || \
    grep -qF 'proxy_plugins."fuse-overlayfs"' "${CONTAINERD_CONFIG}"; }; then
    rm -f "${CONTAINERD_CONFIG}"
    [ -f "${CONTAINERD_CONFIG}.pre-fuse-overlayfs" ] && mv "${CONTAINERD_CONFIG}.pre-fuse-overlayfs" "${CONTAINERD_CONFIG}"
  fi
  if [ -f "${SYSTEMD_DROPIN}" ]; then
    rm -f "${SYSTEMD_DROPIN}"
    systemctl daemon-reload
  fi
  rm -f /usr/local/bin/fuse-overlayfs /usr/local/bin/containerd-fuse-overlayfs-grpc /usr/local/bin/fusermount3 \
    /sbin/mount.fuse3
  echo
  echo "Done. Restart Docker to apply: sudo synopkg stop ${SYNO_DOCKER_SERV_NAME} && sudo synopkg start ${SYNO_DOCKER_SERV_NAME}"
  echo "fuse-overlayfs image data is left in ${FUSE_OVERLAYFS_DATA}; delete it once you no longer need it."
}

#======================================================================================================================
# Main
#======================================================================================================================
if [ "${action}" = 'uninstall' ]; then
  uninstall
  exit 0
fi

echo "=== Synology Docker fuse-overlayfs installer ==="
echo

check_fuse_support
check_overlay_needed
check_storage_driver

work_dir=$(mktemp -d)
trap 'rm -rf "${work_dir}"' EXIT

install_fuse_overlayfs
install_fuse3_tools
install_grpc_snapshotter
create_containerd_config
create_startup_script
configure_dockerd
neutralize_updater
configure_iptables_raw

echo
echo "=== Installation complete ==="
echo
echo "To activate, run:"
echo "  1. Stop Docker:  sudo synopkg stop ${SYNO_DOCKER_SERV_NAME}"
echo "  2. Start fuse-overlayfs services:  sudo ${RC_SCRIPT} start"
echo "  3. Start Docker:  sudo synopkg start ${SYNO_DOCKER_SERV_NAME}"
echo
echo "Or reboot the NAS (the rc.d script starts the services automatically)."
echo
echo "NOTE: Existing images and containers from the previous storage driver will not be visible."
echo "      Pull images and recreate containers; volumes and bind mounts are kept."
