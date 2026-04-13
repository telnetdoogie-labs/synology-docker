#!/bin/bash

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
if [ -d "/var/packages/ContainerManager" ]; then
    readonly FILE="/var/packages/ContainerManager/scripts/start-stop-status"
elif [ -d "/var/packages/Docker" ]; then
    readonly FILE="/var/packages/Docker/scripts/start-stop-status"
fi
INSERTAFTER='iptablestool --insmod "${DockerServName}" ${InsertModules}'
INSERT="    # Added by docker update\n"
INSERT="${INSERT}   # Load raw modules\n"
INSERT="${INSERT}   insmod ${MODULES_FOLDER}/${IP4MODULE}\n"
INSERT="${INSERT}   insmod ${MODULES_FOLDER}/${IP6MODULE}"
KERNEL_VERSION=$(uname -r)
PLATFORM_VERSION=$(/bin/get_key_value /etc.defaults/synoinfo.conf platform_name)
IP4DL="https://raw.githubusercontent.com/telnetdoogie/synology-kernelmodules/main/compiled_modules/${KERNEL_VERSION}/${PLATFORM_VERSION}/${IP4MODULE}"
IP6DL="https://raw.githubusercontent.com/telnetdoogie/synology-kernelmodules/main/compiled_modules/${KERNEL_VERSION}/${PLATFORM_VERSION}/${IP6MODULE}"

echo "Kernel Version: ${KERNEL_VERSION}"
echo "Platform: ${PLATFORM_VERSION}"

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
  IP4_AVAIL=$([ $(curl -I -s -o /dev/null -w "%{http_code}" "$IP4DL") == "200" ] && echo 1 || echo 0)
  IP6_AVAIL=$([ $(curl -I -s -o /dev/null -w "%{http_code}" "$IP6DL") == "200" ] && echo 1 || echo 0)
  if [[ $IP4_AVAIL != 1 || $IP6_AVAIL != 1 ]]; then
    # both files not available for download.
    echo "false"
    return 1 
  else
    echo "true"
    return 0
  fi
}

start_script_loads_modules() {
  if ! grep -q 'Load raw modules' "${FILE}"; then
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
  output_result $KOS_PLACED 

  echo
  echo -n " - kernel modules loaded   ?"
  MODS_LOADED=$(modules_loaded)
  output_result $MODS_LOADED

  echo
  echo -n " - available for download  ?"
  MOD_DL_AVAIL=$(modules_available_for_download)
  output_result $MOD_DL_AVAIL

  echo
  echo -n " - CM script loads modules ?"
  SCRIPT_ADDED=$(start_script_loads_modules)
  output_result $SCRIPT_ADDED
  echo
  echo
}

download_and_place_modules() {
  echo "Downloading and placing modules in /lib/modules folder..." 
  curl -sO ${IP4DL} && echo -n "." || return 1
  curl -sO ${IP6DL} && echo -n "." || return 1
  cp -f ./${IP4MODULE} ${MODULES_FOLDER}/${IP4MODULE} && echo -n "." || return 1
  cp -f ./${IP6MODULE} ${MODULES_FOLDER}/${IP6MODULE} && echo -n "." || return 1
  chown root:root ${MODULES_FOLDER}/${IP4MODULE} ${MODULES_FOLDER}/${IP6MODULE} && echo -n "." || return 1
  chmod 644 ${MODULES_FOLDER}/${IP4MODULE} ${MODULES_FOLDER}/${IP6MODULE} && echo -n "." || return 1
  rm ./${IP4MODULE} ./${IP6MODULE} && echo -n "." || return 1
  echo
}

install_and_validate_modules() { 
  echo "Installing and validating the kernel modules..."
  insmod ${MODULES_FOLDER}/${IP4MODULE} && echo -n "." || return 1
  insmod ${MODULES_FOLDER}/${IP6MODULE} && echo -n "." || return 1
  echo
}

modify_script() {
  echo "Modifying the ContainerManager startup to install modules..." 
  match="^[[:space:]]*${INSERTAFTER}"
  sed -i "/$match/a\\$INSERT" "${FILE}"
}


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

  download_and_place_modules

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
  
  modify_script

  SUCCESS=$(start_script_loads_modules)
  if [[ $SUCCESS != "true" ]]; then
    echo "   There was a problem modifying the start-stop-script."
    echo "   Please create an issue in the github repo and add the contents of this script in the issue:"
    echo "     /var/packages/ContainerManager/scripts/start-stop-status "
    echo "   We cannot continue"
    exit 1
  fi
fi

check_all

