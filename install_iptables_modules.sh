#!/bin/bash

readonly MODULE_CURL_HTTPS_FLAGS=(--proto '=https' --proto-redir '=https' --tlsv1.2)
curl_https_modules() {
  curl "$@" "${MODULE_CURL_HTTPS_FLAGS[@]}"
}

initialize_modules() {
# Test if script has root privileges, exit otherwise
id=$(id -u)
if [[ "${id}" -ne 0 ]]; then
    echo "You need to run this with sudo or as root."
	exit 1
fi

MODULES_FOLDER="/lib/modules"
IP4MODULE="iptable_raw.ko"
IP6MODULE="ip6table_raw.ko"
#Update to work with older Docker versions... untested
if [[ -f "/var/packages/ContainerManager/scripts/start-stop-status" ]]; then
    readonly FILE="/var/packages/ContainerManager/scripts/start-stop-status"
elif [[ -f "/var/packages/Docker/scripts/start-stop-status" ]]; then
    readonly FILE="/var/packages/Docker/scripts/start-stop-status"
else
    echo "Could not locate Container Manager or Docker start-stop-status script."
    exit 1
fi
# shellcheck disable=SC2016 # This is a literal startup-script anchor, not an expansion.
INSERTAFTER='iptablestool --insmod "${DockerServName}" ${InsertModules}'
INSERT="    # Added by docker update\n"
INSERT="${INSERT}   # Load raw modules\n"
INSERT="${INSERT}   insmod ${MODULES_FOLDER}/${IP4MODULE}\n"
INSERT="${INSERT}   insmod ${MODULES_FOLDER}/${IP6MODULE}"
KERNEL_VERSION=$(uname -r)
PLATFORM_VERSION=$(/bin/get_key_value /etc.defaults/synoinfo.conf platform_name)
MODULE_SOURCE_COMMIT='fb894e2c6f7d5c2e81e4c59c27721081f7d487f9'
MODULE_BASE="https://raw.githubusercontent.com/telnetdoogie-labs/synology-kernelmodules/${MODULE_SOURCE_COMMIT}/compiled_modules"
IP4DL="${MODULE_BASE}/${KERNEL_VERSION}/${PLATFORM_VERSION}/${IP4MODULE}"
IP6DL="${MODULE_BASE}/${KERNEL_VERSION}/${PLATFORM_VERSION}/${IP6MODULE}"

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
  IP4MODULE_PRESENT=$([[ -f "$MODULES_FOLDER/$IP4MODULE" ]] && echo 1 || echo 0)
  IP6MODULE_PRESENT=$([[ -f "$MODULES_FOLDER/$IP6MODULE" ]] && echo 1 || echo 0)
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
  if [[ "$IP4_AVAIL" != "200" || "$IP6_AVAIL" != "200" ]]; then
    # both files not available for download.
    echo "false"
    return 1
  else
    echo "true"
    return 0
  fi
}

module_checksums() {
  case "${KERNEL_VERSION}/${PLATFORM_VERSION}" in
    '4.4.302+/apollolake')
      expected_ip4='bdc0737e3193c3fadc0a77e8fc04a67ed3293c05c2c1b1b4105bf9e294f92345'
      expected_ip6='8214a571d7a2359fd59999d1b178dce521b1793db968eeb49f37e2ca51751a7f'
      ;;
    '4.4.302+/broadwell'|'4.4.302+/broadwellnk')
      expected_ip4='4eedf6d6f3fa33d0eb06db1233bcff07674e0c6971c8fa7d1e1b2f4dafcf2853'
      expected_ip6='a06bb502f11729954f5198b6ef2e489f3e8f966c42202c1aa865d674512fd492'
      ;;
    '4.4.302+/broadwellntbap')
      expected_ip4='e56364f1ded5b41bb0160c80868004064ca8990825366799903558492363a802'
      expected_ip6='62719570fcb1ff756c953f039deae154e678ab5c5ce96582fc29c61767870698'
      ;;
    '4.4.302+/denverton')
      expected_ip4='9a23cda02138c07a2d2c738250f30eb5a38d01f85696f4c4a27b1ee115f2be06'
      expected_ip6='1e940a5b1419b410b1830512ecee4d09397f4de5a19e389cdc867e684570037b'
      ;;
    '4.4.302+/geminilake')
      expected_ip4='ff816de940720d4b0181d9309c050643cf0b34ae0982767d217e05987f2c12ac'
      expected_ip6='a6069c3e25051e8ea72c483681ee58667f51c7821be80f2a2d93fe9cd073652a'
      ;;
    '4.4.302+/purley')
      expected_ip4='67230712f39373869668751860650bc487ded0af16874c6a4de587d79cf131c2'
      expected_ip6='38d7ca3949938d1675fd0f5818a67bc8ce9bf0713f31540014999c103784ca1e'
      ;;
    '4.4.302+/r1000'|'4.4.302+/v1000')
      expected_ip4='7c9bc2c8822c367bf471c9defd5633be9167f5fddc08fded8205e460017ca001'
      expected_ip6='03b020c5a7349f330106d0c684e163aca1a01cf79e46a7ec81abfcb1c894ff67'
      ;;
    '5.10.55+/epyc7002')
      expected_ip4='b28072b50e296a3762dc15240531037c5486b3b0c212c8caf67c0380f6b8f1c6'
      expected_ip6='afe8768ac26102d2cf9ace5ad2e1570f2ad3f93019a4ff094da95458d16ed636'
      ;;
    '5.10.55+/r1000nk')
      expected_ip4='d44dcd11d10f900deef2c5a0e61fa473172c8fdd7d1e187402a8e841fe0efc75'
      expected_ip6='646f6a68d49950c5e6e1037eb14a203268e4f01e0338e93eb5f5ed4ca125469f'
      ;;
    '5.10.55+/v1000nk')
      expected_ip4='682adcdef5dc0e4d493b198243b3ee21a687110dd1786e22e89ca58a025ed64f'
      expected_ip6='d9e07565d91594fc2650dc3966e74c2c0297e7a11a3a43318d117a6c83885a7a'
      ;;
    *)
      printf 'No verified modules for kernel %s and platform %s\n' "$KERNEL_VERSION" "$PLATFORM_VERSION" >&2
      return 1
      ;;
  esac
}

start_script_loads_modules() {
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
  if [[ "$KOS_PLACED" = 'true' ]]; then
    MOD_DL_AVAIL='true'
    echo " not needed (already installed)"
  else
    MOD_DL_AVAIL=$(modules_available_for_download)
    output_result "$MOD_DL_AVAIL"
  fi

  echo
  echo -n " - CM script loads modules ?"
  SCRIPT_ADDED=$(start_script_loads_modules)
  output_result "$SCRIPT_ADDED"
  echo
  echo
}

download_and_place_modules() (
  echo "Downloading and placing modules in /lib/modules folder..."
  module_checksums || return 1
  command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum is required to verify kernel modules" >&2; return 1; }
  module_download_dir=$(mktemp -d "${TMPDIR:-/tmp}/synology-docker-modules.XXXXXX") || return 1
  trap 'rm -rf "$module_download_dir"' EXIT
  curl_https_modules -fsSL --connect-timeout 10 --max-time 120 "$IP4DL" -o "$module_download_dir/$IP4MODULE" && echo -n "." || return 1
  curl_https_modules -fsSL --connect-timeout 10 --max-time 120 "$IP6DL" -o "$module_download_dir/$IP6MODULE" && echo -n "." || return 1
  if [[ "$(sha256sum "$module_download_dir/$IP4MODULE" | cut -d' ' -f1)" != "$expected_ip4" ]] ||
    [[ "$(sha256sum "$module_download_dir/$IP6MODULE" | cut -d' ' -f1)" != "$expected_ip6" ]]; then
    echo "Downloaded kernel module checksum did not match the pinned release" >&2
    return 1
  fi
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
  echo "Modifying the ContainerManager startup to install modules..."
  match="^[[:space:]]*${INSERTAFTER}"
  sed -i "/$match/a\\$INSERT" "${FILE}"
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

check_all
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  initialize_modules
  run_modules
fi
