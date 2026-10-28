#!/bin/bash

readonly MODULE_CURL_HTTPS_FLAGS=(--proto '=https' --proto-redir '=https' --tlsv1.2)
curl_https_modules() {
  curl "$@" "${MODULE_CURL_HTTPS_FLAGS[@]}"
}

initialize_modules() {
# Test if script has root privileges, exit otherwise
id=$(id -u)
if [ "${id}" -ne 0 ]; then
    echo "You need to run this with sudo or as root."
	exit 1
fi

MODULES_FOLDER="/lib/modules"
IP4MODULE="iptable_raw.ko"
IP6MODULE="ip6table_raw.ko"
#Update to work with older Docker versions... untested
if [ -f "/var/packages/ContainerManager/scripts/start-stop-status" ]; then
    readonly FILE="/var/packages/ContainerManager/scripts/start-stop-status"
elif [ -f "/var/packages/Docker/scripts/start-stop-status" ]; then
    readonly FILE="/var/packages/Docker/scripts/start-stop-status"
else
    echo "Could not locate Container Manager or Docker start-stop-status script."
    exit 1
fi
# shellcheck disable=SC2016 # This is a literal startup-script anchor, not an expansion.
INSERTAFTER='iptablestool --insmod "${DockerServName}" ${InsertModules}'
# On DSM 7, dockerd runs as a systemd unit. Loading the modules from a drop-in for that unit survives Container
# Manager package updates, which replace start-stop-status (and with it the older inserted insmod lines).
DOCKERD_UNIT=$(sed -n 's/^Dockerd="\(.*\)"[[:space:]]*$/\1/p' "${FILE}" | head -1)
if [ -n "${DOCKERD_UNIT}" ] && [ -d /run/systemd/system ]; then
  USE_SYSTEMD='true'
  DROPIN_DIR="/etc/systemd/system/${DOCKERD_UNIT}.service.d"
  DROPIN="${DROPIN_DIR}/iptables-raw-modules.conf"
else
  USE_SYSTEMD='false'
fi
INSERT="    # Added by docker update\n"
INSERT="${INSERT}   # Load raw modules\n"
INSERT="${INSERT}   insmod ${MODULES_FOLDER}/${IP4MODULE}\n"
INSERT="${INSERT}   insmod ${MODULES_FOLDER}/${IP6MODULE}"
KERNEL_VERSION=$(uname -r)
PLATFORM_VERSION=$(/bin/get_key_value /etc.defaults/synoinfo.conf platform_name)
IP4DL="https://raw.githubusercontent.com/telnetdoogie-labs/synology-kernelmodules/main/compiled_modules/${KERNEL_VERSION}/${PLATFORM_VERSION}/${IP4MODULE}"
IP6DL="https://raw.githubusercontent.com/telnetdoogie-labs/synology-kernelmodules/main/compiled_modules/${KERNEL_VERSION}/${PLATFORM_VERSION}/${IP6MODULE}"

echo "Kernel Version: ${KERNEL_VERSION}"
echo "Platform: ${PLATFORM_VERSION}"
}

output_result(){
  if [[ $1 == "true" ]]; then
    echo -n " 🟢"
  else
    echo -n " 🔴"
  fi
}

modules_loaded() {
  # Check if the kernel modules are already loaded
  lsmod | grep -q ip6table_raw
  HAS_IP6RAW=$?
  lsmod | grep -q iptable_raw
  HAS_IP4RAW=$?
  if [[ $HAS_IP6RAW -ne 0 || $HAS_IP4RAW -ne 0 ]]; then
    # both modules not loaded
    echo "false"
    return 1
  else
    # both modules loaded
    echo "true"
    return 0
  fi
}

module_files_present() {
  # Check if the kernel modules are present in the modules folder
  IP4MODULE_PRESENT=$([ -f "$MODULES_FOLDER/$IP4MODULE" ] && echo 1 || echo 0)
  IP6MODULE_PRESENT=$([ -f "$MODULES_FOLDER/$IP6MODULE" ] && echo 1 || echo 0)
  if [[ $IP4MODULE_PRESENT != 1 || $IP6MODULE_PRESENT != 1 ]]; then
    # both files were not present
    echo "false"
    return 1
  else
    # both files were present
    echo "true"
    return 0
  fi
}

modules_available_for_download() {
  # Check if the modules can be downloaded
  IP4_AVAIL=$(curl_https_modules -ILsS --connect-timeout 10 --max-time 30 -o /dev/null -w "%{http_code}" "$IP4DL")
  IP6_AVAIL=$(curl_https_modules -ILsS --connect-timeout 10 --max-time 30 -o /dev/null -w "%{http_code}" "$IP6DL")
  if [ "$IP4_AVAIL" != "200" ] || [ "$IP6_AVAIL" != "200" ]; then
    # both files not available for download.
    echo "false"
    return 1
  else
    echo "true"
    return 0
  fi
}

start_script_loads_modules() {
  if [[ "${USE_SYSTEMD}" == "true" ]]; then
    # the systemd drop-in loads the modules before dockerd starts
    if [ -f "${DROPIN}" ]; then
      echo "true"
      return 0
    fi
    echo "false"
    return 1
  fi
  if ! grep -Fq "insmod ${MODULES_FOLDER}/${IP4MODULE}" "$FILE" ||
    ! grep -Fq "insmod ${MODULES_FOLDER}/${IP6MODULE}" "$FILE"; then
    # the script does not currently load the modules
    echo "false"
    return 1
  else
    # the script currently loads the modules
    echo "true"
    return 0
  fi
}

check_all() {
  echo
  echo -n " - .ko files in place      ?"
  KOS_PLACED=$(module_files_present)
  output_result "$KOS_PLACED"

  echo
  echo -n " - kernel modules loaded   ?"
  MODS_LOADED=$(modules_loaded)
  output_result "$MODS_LOADED"

  echo
  echo -n " - available for download  ?"
  if [ "$KOS_PLACED" = 'true' ]; then
    MOD_DL_AVAIL='true'
    echo " not needed (already installed)"
  else
    MOD_DL_AVAIL=$(modules_available_for_download)
    output_result "$MOD_DL_AVAIL"
  fi

  echo
  echo -n " - modules load with Docker?"
  SCRIPT_ADDED=$(start_script_loads_modules)
  output_result "$SCRIPT_ADDED"
  echo
  echo
}

download_and_place_modules() (
  echo "Downloading and placing modules in /lib/modules folder..."
  module_download_dir=$(mktemp -d "${TMPDIR:-/tmp}/synology-docker-modules.XXXXXX") || return 1
  trap 'rm -rf "$module_download_dir"' EXIT
  curl_https_modules -fsSL --connect-timeout 10 --max-time 120 "$IP4DL" -o "$module_download_dir/$IP4MODULE" && echo -n "." || return 1
  curl_https_modules -fsSL --connect-timeout 10 --max-time 120 "$IP6DL" -o "$module_download_dir/$IP6MODULE" && echo -n "." || return 1
  cp -f "$module_download_dir/$IP4MODULE" "$MODULES_FOLDER/$IP4MODULE" && echo -n "." || return 1
  cp -f "$module_download_dir/$IP6MODULE" "$MODULES_FOLDER/$IP6MODULE" && echo -n "." || return 1
  chown root:root "$MODULES_FOLDER/$IP4MODULE" "$MODULES_FOLDER/$IP6MODULE" && echo -n "." || return 1
  chmod 644 "$MODULES_FOLDER/$IP4MODULE" "$MODULES_FOLDER/$IP6MODULE" && echo -n "." || return 1
  echo
)

install_and_validate_modules() {
  echo "Installing and validating the kernel modules..."
  insmod ${MODULES_FOLDER}/${IP4MODULE} && echo -n "." || return 1
  insmod ${MODULES_FOLDER}/${IP6MODULE} && echo -n "." || return 1
  echo
}

modify_script() {
  if [[ "${USE_SYSTEMD}" == "true" ]]; then
    install_dropin
    return
  fi
  echo "Modifying the ContainerManager startup to install modules..."
  match="^[[:space:]]*${INSERTAFTER}"
  sed -i "/$match/a\\$INSERT" "${FILE}"
}

install_dropin() {
  echo "Adding a systemd drop-in to load the modules before ${DOCKERD_UNIT} starts..."
  mkdir -p "${DROPIN_DIR}"
  {
    echo "# Added by synology-docker (install_iptables_modules.sh): load the iptables raw modules Docker 28+ needs"
    echo "[Service]"
    echo "ExecStartPre=-/bin/sh -c 'lsmod | grep -q \"^iptable_raw \" || insmod ${MODULES_FOLDER}/${IP4MODULE}'"
    echo "ExecStartPre=-/bin/sh -c 'lsmod | grep -q \"^ip6table_raw \" || insmod ${MODULES_FOLDER}/${IP6MODULE}'"
  } > "${DROPIN}"
  systemctl daemon-reload
}

# Older versions of this script inserted the insmod lines into start-stop-status. With the drop-in in place they're
# no longer needed, so remove them (the identically-commented IP forwarding block is left alone).
remove_script_insert() {
  if ! grep -q 'Load raw modules' "${FILE}"; then
    return
  fi
  echo "Removing the old module loading lines from ${FILE}..."
  sed -i '/^[[:space:]]*# Added by docker update[[:space:]]*$/{N;/\n[[:space:]]*# Load raw modules[[:space:]]*$/d}' "${FILE}"
  sed -i '/^[[:space:]]*# Load raw modules[[:space:]]*$/d' "${FILE}"
  sed -i '/^[[:space:]]*insmod \/lib\/modules\/ip6\{0,1\}table_raw\.ko[[:space:]]*$/d' "${FILE}"
}


run_modules() {
# Start the main flow
check_all

# Above all else, the files need to be available and placed appropriately.
if [[ $KOS_PLACED != "true" ]]; then
  # the files are not in place. We will need to download them.
  if [[ $MOD_DL_AVAIL != "true" ]]; then
    # they are not available for download.
    echo "   The kernel modules for your platform and kernel are not available for download."
    echo "   You can compile them yourself and place them in /lib/modules or request a compile for your platform"
    echo "   We cannot continue without these modules."
    exit 1
  fi

  download_and_place_modules || exit 1

  SUCCESS=$(module_files_present)
  if [[ $SUCCESS != "true" ]]; then
    echo "   There was a problem downloading and copying the .ko files to your device."
    echo "   We cannot continue."
    exit 1
  fi

fi

# if modules are in the correct place, let's make sure they can be loaded.
if [[ $MODS_LOADED != "true" ]]; then
  # the modules are not loaded; we need to load them and check for validity

  install_and_validate_modules

  SUCCESS=$(modules_loaded)
  if [[ $SUCCESS != "true" ]]; then
    echo "   There was a problem installing the modules on your device."
    echo "   Check that the correct .ko files are installed, and valid permissions are on the files."
    echo "   We cannot continue unless modules are valid and loadable."
    exit 1
  fi
fi

# Modules are valid and installed / installable. Now we need to make sure they are loaded by the start script.
if [[ $SCRIPT_ADDED != "true" ]]; then
  # the modules aren't loaded with the start-stop-status script. We will need to modify it.

  modify_script || exit 1

  SUCCESS=$(start_script_loads_modules)
  if [[ $SUCCESS != "true" ]]; then
    echo "   There was a problem modifying the start-stop-script."
    echo "   Please create an issue in the github repo and add the contents of this script in the issue:"
    echo "     /var/packages/ContainerManager/scripts/start-stop-status "
    echo "   We cannot continue"
    exit 1
  fi
fi

if [[ "${USE_SYSTEMD}" == "true" ]]; then
  remove_script_insert
fi

check_all
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  initialize_modules
  run_modules
fi
