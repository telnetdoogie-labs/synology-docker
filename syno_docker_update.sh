#!/bin/sh

#======================================================================================================================
# Title         : syno_docker_update.sh
# Date          : April 30th, 2026
# Usage         : sudo ./syno_docker_update.sh [OPTIONS] COMMAND
# Repository    : https://github.com/telnetdoogie/synology-docker.git
#======================================================================================================================

#======================================================================================================================
# Displays error message on console and terminates with non-zero error.
#======================================================================================================================
# Arguments:
#   $1 - Error message to display.
# Outputs:
#   Writes error message to stderr, non-zero exit code.
#======================================================================================================================
terminate() {
  printf "${RED}${BOLD}%s${NC}\n" "ERROR: $1"
  exit 1
}

terminate_with_warning() {
  printf "${RED}${BOLD}%s${NC}\n" "Exiting - $1"
  exit 1
}

validate_dependencies(){
  # Define the presence of dependent files
  DEPENDENT_FILES=(
    "container_recreate.sh"
    "syno_docker_list_containers.sh"
    "syno_docker_switch_logger.sh")
  # Loop through each file in the array and check if it exists
  for file in "${DEPENDENT_FILES[@]}"; do
    if [[ ! -f "$SCRIPT_DIR/$file" ]]; then
      terminate "Error: Required file '$file' is missing in the script directory ($SCRIPT_DIR). You may need to do a git pull."
    fi
  done
}

#======================================================================================================================
# Constants
#======================================================================================================================
readonly RED='\e[31m' # Red color
readonly NC='\e[m' # No color / reset
readonly BOLD='\e[1m' # Bold font
readonly SCRIPT_DIR="$(dirname "$(realpath "$0")")"
readonly DSM_SUPPORTED_VERSION=6
readonly DEFAULT_DOCKER_VERSION='20.10.11'
readonly DEFAULT_COMPOSE_VERSION='2.1.1'
readonly CPU_ARCH='x86_64'
readonly DOWNLOAD_DOCKER="https://download.docker.com/linux/static/stable/${CPU_ARCH}"
readonly DOWNLOAD_GITHUB='https://github.com/docker/compose'
readonly PINNED_RUNC='https://github.com/opencontainers/runc/releases/download/v1.3.2/runc.amd64'
readonly GITHUB_API_COMPOSE='https://api.github.com/repos/docker/compose/releases/latest'
if [ -d "/var/packages/ContainerManager" ]; then
  readonly SYNO_DOCKER_DIR='/var/packages/ContainerManager'
  readonly SYNO_DOCKER_SERV_NAME='ContainerManager'
elif [ -d "/var/packages/Docker" ]; then
  readonly SYNO_DOCKER_DIR='/var/packages/Docker'
  readonly SYNO_DOCKER_SERV_NAME='Docker'
fi
if [ -z "$SYNO_DOCKER_DIR" ]; then
  terminate "Docker (or ContainerManager) folder was not found."
fi
readonly SYNO_DOCKER_BIN_PATH="${SYNO_DOCKER_DIR}/target/usr"
readonly SYNO_DOCKER_BIN="${SYNO_DOCKER_BIN_PATH}/bin"
readonly SYNO_DOCKER_SCRIPT_PATH="${SYNO_DOCKER_DIR}/scripts"
readonly SYNO_DOCKER_SCRIPT="${SYNO_DOCKER_SCRIPT_PATH}/start-stop-status"
readonly SYNO_DOCKER_JSON_PATH="${SYNO_DOCKER_DIR}/etc"
readonly SYNO_DOCKER_JSON="${SYNO_DOCKER_JSON_PATH}/dockerd.json"
readonly SYNO_DOCKER_SCRIPT_FORWARDING="            # Added by docker update\n          iptables -P FORWARD ACCEPT\n          iptables -C FORWARD -j DOCKER-FORWARD 2>/dev/null || iptables -I FORWARD 1 -j DOCKER-FORWARD"
readonly SYNO_SERVICE_STOP_TIMEOUT='10m'
RUNNING_CONTAINERS=$(docker ps -q 2>/dev/null | awk 'NF' | wc -l)
if [ $? -ne 0 ]; then
  RUNNING_CONTAINERS=0
fi
if [ "$RUNNING_CONTAINERS" -gt 5 ]; then
  computed_timeout=$(( (RUNNING_CONTAINERS * 3) / 2 ))
  if [ "$computed_timeout" -lt 10 ]; then
    readonly SYNO_SERVICE_START_TIMEOUT=10m
  else
    readonly SYNO_SERVICE_START_TIMEOUT=$(( (RUNNING_CONTAINERS * 3) / 2 ))m
  fi
else
  readonly SYNO_SERVICE_START_TIMEOUT=10m
fi

#======================================================================================================================
# Variables
#======================================================================================================================
dsm_major_version=''
docker_version=''
compose_version=''
temp_dir="/tmp/docker_update"
backup_dir="${PWD}"
download_dir="${temp_dir}"
docker_backup_filename="docker_backup_$(date +%Y%m%d_%H%M%S).tgz"
skip_docker_update='false'
skip_compose_update='false'
skip_driver_update='false'
force='false'
stage='false'
command=''
target='all'
target_docker_version=''
target_compose_version=''
backup_filename_flag='false'
step=0
total_steps=0
install_iptables_modules='false'
skip_iptables_modules='false'


#======================================================================================================================
# Helper Functions
#======================================================================================================================

#======================================================================================================================
# Display usage message.
#======================================================================================================================
# Globals:
#   - backup_dir
# Outputs:
#   Writes message to stdout.
#======================================================================================================================
usage() {
  echo "Usage: $0 [OPTIONS] COMMAND"
  echo
  echo "Options:"
  echo "  -b, --backup NAME      Name of the backup (defaults to 'docker_backup_YYMMDDHHMMSS.tgz')"
  echo "  -c, --compose VERSION  Docker Compose target version (defaults to latest)"
  echo "  -d, --docker VERSION   Docker target version (defaults to latest)"
  echo "  -f, --force            Force update (bypass compatibility check and confirmation check)"
  echo "  -p, --path PATH        Path of the backup (defaults to '${backup_dir}')"
  echo "  -s, --stage            Stage only, do not actually replace binaries or configuration of log driver"
  echo "  -t, --target           Target to update, either 'all' (default), 'engine', 'compose', or 'driver'"
  echo "  --skip-iptables        Do not check for / install iptables modules"

  echo
  echo "Commands:"
  echo "  backup                 Create a backup of Docker and Docker Compose binaries and dockerd configuration"
  echo "  download [PATH]        Download Docker and Docker Compose binaries to PATH"
  echo "  install [PATH]         Update Docker and Docker Compose from files on PATH"
  echo "  restore                Restore Docker and Docker Compose from backup"
  echo "  update                 Update Docker and Docker Compose to target version (creates backup first)"
  echo "  logger                 Update ONLY the logging driver to the local logger (a proactive preparation step)"
  echo "  validate               Validates versions available for update"
  echo
}

#======================================================================================================================
# Print current progress to the console and shows progress against total number of steps.
#======================================================================================================================
# Arguments:
#   $1 - Progress message to display.
# Outputs:
#   Writes message to stdout.
#======================================================================================================================
print_status() {
  step=$((step + 1))
  printf "${BOLD}%s${NC}\n" "Step ${step} from ${total_steps}: $1"
}

#======================================================================================================================
# Detects the current versions for DSM, Docker, and Docker Compose and displays them on the console. It also verifies
# the host runs DSM and that Docker (including Compose) is already installed, unless 'force' is set to true.
#======================================================================================================================
# Globals:
#   - dsm_version
#   - dsm_major_version
#   - docker_version
#   - compose_version
#   - force
# Outputs:
#   Writes message to stdout. Terminates with non-zero exit code if host is incompatible, unless 'force' is true.
#======================================================================================================================
detect_current_versions() {
  # Detect current DSM version
  dsm_version=$(test -f '/etc.defaults/VERSION' && < '/etc.defaults/VERSION' grep '^productversion' | \
    cut -d'=' -f2 | sed "s/\"//g")
  dsm_major_version=$(test -f '/etc.defaults/VERSION' && < '/etc.defaults/VERSION' grep '^majorversion' | \
    cut -d'=' -f2 | sed "s/\"//g")

  # Detect current Docker version
  docker_version=$(docker -v 2>/dev/null | grep -Eo "[0-9]*.[0-9]*.[0-9]*," | cut -d',' -f 1)

  # Detect current Docker Compose version
  compose_version=$(docker-compose -v 2>/dev/null | grep -Eo "v[0-9]+.[0-9]*.[0-9]*" | cut -c 2-)
  if [ -z "${compose_version}" ] ; then
    compose_version=$(docker-compose -v 2>/dev/null | grep -Eo "[0-9]*.[0-9]*.[0-9]*," | cut -d',' -f 1)
  fi

  containerd_version=$(containerd -version | grep -Eo "v[0-9]+.[0-9]+.[0-9]+" | cut -c 2-)
  runc_version=$(runc -version | grep -Eo "v[0-9]+.[0-9]+.[0-9]+" | cut -c 2-)

  echo "Current DSM version: ${dsm_version:-Unknown}"
  echo "Current Docker version: ${docker_version:-Unknown}"
  echo "Current Docker Compose version: ${compose_version:-Unknown}"
  echo "Current containerd version: ${containerd_version:-Unknown}"
  echo "Current runc version: ${runc_version:-Unknown}"

  if [ "${force}" != 'true' ] ; then
    validate_current_version
  fi
}

#======================================================================================================================
# Verifies the host has the right CPU, runs DSM and that Docker (including Compose) is already installed.
#======================================================================================================================
# Globals:
#   - dsm_version
#   - docker_version
#   - compose_version
#   - skip_docker_update
#   - skip_compose_update
# Outputs:
#   Terminates with non-zero exit code if host is incompatible.
#======================================================================================================================
validate_current_version() {
  # Test host has supported CPU, exit otherwise
  current_arch=$(uname -m)
  if [ "${current_arch}" != "${CPU_ARCH}" ]; then
    terminate "This script supports ${CPU_ARCH} CPUs only, use --force to override"
  fi

  # Test if host is DSM 6 or later, exit otherwise
  if [ "${dsm_major_version}" -lt "${DSM_SUPPORTED_VERSION}" ] ; then
    terminate "This script supports DSM 6.x or later only, use --force to override"
  fi

  # Test Docker version is present, exit otherwise
  if [ -z "${docker_version}" ] && [ "${skip_docker_update}" = 'false' ] ; then
    terminate "Could not detect current Docker version, use --force to override"
  fi

  # Test Docker Compose version is present, exit otherwise
  if [ -z "${compose_version}" ] && [ "${skip_compose_update}" = 'false' ]; then
    terminate "Could not detect current Docker Compose version, use --force to override"
  fi
}

#======================================================================================================================
# Detects Docker versions downloaded on disk and updates the target Docker version accordingly. Downloads are ignored
# if a specific target Docker version is already specified.
#======================================================================================================================
# Globals:
#   - target_docker_version
# Outputs:
#   Updated 'target_docker_version'.
#======================================================================================================================
detect_available_downloads() {
  if [ -z "${target_docker_version}" ] ; then
    downloads=$(find "${download_dir}/" -maxdepth 1 -type f | cut -c 4- | \
      grep -Eo 'docker-[0-9]*.[0-9]*.[0-9]*(-ce)?.tgz')
    latest_download=$(echo "${downloads}" | sort -bt. -k1,1 -k2,2n -k3,3n -k4,4n -k5,5n | tail -1)
    target_docker_version=$(echo "${latest_download}" | sed "s/docker-//g" | sed "s/.tgz//g")
  fi
}

#======================================================================================================================
# Detects latest stable versions of Docker and Docker Compose available for download. The detection is skipped if a
# specific target Docker and/or Compose version is already specified. Default versions are assigned if the detection
# fails for some reason.
#======================================================================================================================
# Globals:
#   - target_docker_version
#   - target_compose_version
#   - skip_docker_update
#   - skip_compose_update
# Outputs:
#   Updated 'target_docker_version' and 'target_compose_version'.
#======================================================================================================================
detect_available_versions() {
  # Detect latest available Docker version
  if [ -z "${target_docker_version}" ] && [ "${skip_docker_update}" = 'false' ] ; then
    docker_bin_files=$(curl -s "${DOWNLOAD_DOCKER}/" | grep -Eo '>docker-[0-9]*.[0-9]*.[0-9]*(-ce)?.tgz' | cut -c 2-)
    latest_docker_bin="$(echo "${docker_bin_files}" | sort -bt. -k1,1 -k2,2n -k3,3n -k4,4n -k5,5n | tail -1)"
    target_docker_version=$(echo "${latest_docker_bin}" | sed "s/docker-//g" | sed "s/.tgz//g" )

    if [ -z "${target_docker_version}" ] ; then
      echo "Could not detect Docker versions available for download, setting default value"
      target_docker_version="${DEFAULT_DOCKER_VERSION}"
    fi
  fi

  # Detect latest available stable Docker Compose version (ignores release candidates)
  if [ -z "${target_compose_version}" ] && [ "${skip_compose_update}" = 'false' ] ; then
    target_compose_version=$(curl -s "${GITHUB_API_COMPOSE}" | jq -r '.tag_name | ltrimstr("v")')

    if [ -z "${target_compose_version}" ] || [ "${target_compose_version}" = "null" ] ; then
      echo "Could not detect Docker Compose versions available for download, setting default value"
      target_compose_version="${DEFAULT_COMPOSE_VERSION}"
    fi
  fi
}

#======================================================================================================================
# Validates the target versions for Docker and Docker Compose are defined, exits otherwise.
#======================================================================================================================
# Globals:
#   - target_docker_version
#   - target_compose_version
#   - skip_docker_update
#   - skip_compose_update
# Outputs:
#   Terminates with non-zero exit code if target version is unavailable for either Docker or Docker Compose.
#======================================================================================================================
validate_available_versions() {
  # Test Docker is available for download, exit otherwise
  if [ -z "${target_docker_version}" ] && [ "${skip_docker_update}" = 'false' ] ; then
    terminate "Could not find Docker binaries for downloading"
  fi

  # Test Docker Compose is available for download, exit otherwise
  if [ -z "${target_compose_version}" ] && [ "${skip_compose_update}" = 'false' ] ; then
    terminate "Could not find Docker Compose binaries for downloading"
  fi
}

#======================================================================================================================
# Validates downloaded files for Docker and Docker Compose are available on the download path. The Docker binaries are
# expected to be present as tar archive, whilst Docker compose should be a single binary file. The script exits if
# either file is missing.
#======================================================================================================================
# Globals:
#   - download_dir
#   - target_docker_version
#   - target_compose_version
#   - skip_docker_update
#   - skip_compose_update
# Outputs:
#   Terminates with non-zero exit code if downloaded files for either Docker or Docker Compose are unavailable.
#======================================================================================================================
validate_downloaded_versions() {
  # Test Docker archive is available on path
  target_docker_bin="docker-${target_docker_version}.tgz"
  if [ ! -f "${download_dir}/${target_docker_bin}" ] && [ "${skip_docker_update}" = 'false' ] ; then
    terminate "Could not find Docker archive (${download_dir}/${target_docker_bin})"
  fi

  # Test Docker-compose binary is available on path
  if [ ! -f "${download_dir}/docker-compose" ] && [ "${skip_compose_update}" = 'false' ] ; then
    terminate "Could not find Docker compose binary (${download_dir}/docker-compose)"
  fi
}

#======================================================================================================================
# Validates if a provided version string conforms to the expected SemVer pattern. The pattern should resemble
# 'major.minor.revision'. For example, '6.2.3' is a valid version string, while '6.1' is not.
#======================================================================================================================
# Arguments:
#   $1 - Version string to be verified.
#   $2 - Error message.
# Outputs:
#   Terminates with non-zero exit code if the version string does conform to the expected pattern.
#======================================================================================================================
validate_version_input() {
  validation=$(echo "$1" | grep -Eo '^[0-9]+\.[0-9]+\.[0-9]+$')
  if [ "${validation}" != "$1" ] ; then
    usage
    terminate "$2"
  fi
}

#======================================================================================================================
# Verifies if the provided filename for the Docker backup is provided, exists otherwise. The backup directory and
# backup filename are updated if the filename contains a path.
#======================================================================================================================
# Globals:
#   - backup_dir
#   - docker_backup_filename
# Arguments:
#   $1 - Error message.
# Outputs:
#   Terminates with non-zero exit code if the provided backup filename is missing.
#======================================================================================================================
validate_backup_filename() {
  # check filename is provided
  prefix=$(echo "${docker_backup_filename}" | cut -c1)
  if [ -z "${docker_backup_filename}" ] || [ "${prefix}" = "-" ] ; then
    usage
    terminate "$1"
  fi

  # split into directory and filename if applicable
  # TODO: test
  basepath=$(dirname "${docker_backup_filename}")
  if [ -z "${basepath}" ] || [ "${basepath}" != "." ]; then
    abs_path_and_file=$(readlink -f "${docker_backup_filename}")
    backup_dir=$(dirname "${abs_path_and_file}")
    docker_backup_filename=$(basename "${abs_path_and_file}")
  fi
}

#======================================================================================================================
# Verifies if the provided download directory is provided and available, exists otherwise. The download directory is
# formatted as absolute path.
#======================================================================================================================
# Globals:
#   - download_dir
# Arguments:
#   $1 - Error message when path is not specified
#   $2 - Error message when path is not found
# Outputs:
#   Terminates with non-zero exit code if the provided download path is missing or unavailable. Formats the download
#   directory as absolute path.
#======================================================================================================================
validate_provided_download_path() {
  # check PATH is provided
  prefix=$(echo "${download_dir}" | cut -c1)
  if [ -z "${download_dir}" ] || [ "${prefix}" = "-" ] ; then
    usage
    terminate "$1"
  fi

  # cut trailing '/' and convert to absolute path
  download_dir=$(readlink -f "${download_dir}")

  # check PATH exists
  if [ ! -d "${download_dir}" ] ; then
    usage
    terminate "$2"
  fi
}

#======================================================================================================================
# Verifies if the provided backup directory is provided and available, exists otherwise. The backup directory should
# also differ from the temp path, to avoid accidentaly removing the backup files. The backup directory is formatted as
# absolute path.
#======================================================================================================================
# Globals:
#   - backup_dir
# Arguments:
#   $1 - Error message when path is not specified
#   $2 - Error message when path is not found
#   $3 - Error message when backup path equals temp directory
# Outputs:
#   Terminates with non-zero exit code if the provided backup path is missing, unavailable, or invalid. Formats the
#   backup directory as absolute path.
#======================================================================================================================
validate_provided_backup_path() {
  # check PATH is provided
  prefix=$(echo "${backup_dir}" | cut -c1)
  if [ -z "${backup_dir}" ] || [ "${prefix}" = "-" ] ; then
    usage
    terminate "$1"
  fi

  # cut trailing '/' and convert to absolute path
  backup_dir=$(readlink -f "${backup_dir}")

  # check PATH exists
  if [ ! -d "${backup_dir}" ] ; then
    usage
    terminate "$2"
  fi

  # confirm backup dir is different from temp dir
  if [ "${backup_dir}" = "${temp_dir}" ] ; then
    usage
    terminate "$3"
  fi
}

#======================================================================================================================
# Validates if the specified target is supported. Supported targets are 'all', 'engine', 'compose', or 'driver'. If no
# target is specified, the default value is 'all'. The validation is case sensitive.
#======================================================================================================================
# Globals:
#   - target
#   - skip_docker_update
#   - skip_compose_update
#   - skip_driver_update
# Arguments:
#   $1 - Error message when target is invalid
# Outputs:
#   Terminates with non-zero exit code if the specified target is invalid.
#======================================================================================================================
validate_target() {
  case "${target}" in
    all )
      skip_docker_update='false'
      skip_compose_update='false'
      skip_driver_update='false'
      ;;
    engine )
      skip_docker_update='false'
      skip_compose_update='true'
      skip_driver_update='false'
      ;;
    compose )
      skip_docker_update='true'
      skip_compose_update='false'
      skip_driver_update='true'
      ;;
    driver )
      skip_docker_update='true'
      skip_compose_update='true'
      skip_driver_update='false'
      ;;
    * )
      usage
      terminate "$1"
  esac
}

#======================================================================================================================
# Validates if the target version for either Docker or Docker Compose is newer than the currently installed version.
# Terminates the script if both Docker and Docker Compose are already up to date, unless an update is forced.
# Individual updates for either Docker or Docker Compose are skipped if they are already update to date, unless forced.
#======================================================================================================================
# Globals:
#   - compose_version
#   - docker_version
#   - force
#   - skip_compose_update
#   - skip_docker_update
#   - target_compose_version
#   - target_docker_version
#   - total_steps
# Outputs:
#   Terminates with non-zero exit code if both Docker and Docker Compose are already up to date, unless forced.
#======================================================================================================================
define_update() {
  if [ "${force}" != 'true' ] ; then
    if [ "${docker_version}" = "${target_docker_version}" ] && \
      [ "${compose_version}" = "${target_compose_version}" ] ; then
      terminate_with_warning "Already on target version for Docker and Docker Compose"
    fi
    major="${target_docker_version%%.*}"
    if [[ "$major" -ge 28 && "${skip_iptables_modules}" = 'false' ]]; then
      install_iptables_modules='true'
      total_steps=$((total_steps+1))
    fi
    if [ "${docker_version}" = "${target_docker_version}" ] && [ "${skip_docker_update}" = 'false' ] ; then
      skip_docker_update='true'
      total_steps=$((total_steps-1))
    fi
    if [ "${compose_version}" = "${target_compose_version}" ] && [ "${skip_compose_update}" = 'false' ]; then
      skip_compose_update='true'
      total_steps=$((total_steps-1))
    fi

    log_driver=$(jq -r '.["log-driver"] // empty' "${SYNO_DOCKER_JSON}")
    if [ "$log_driver" = "local" ]; then
      skip_driver_update='true'
      total_steps=$((total_steps-1))
    fi
  fi
}

#======================================================================================================================
# Verifies a backup file is provided as argument for a restore operation.
#======================================================================================================================
# Globals:
#   - backup_filename_flag
# Outputs:
#   Terminates with non-zero exit code if no backup file is provided.
#======================================================================================================================
define_restore() {
  if [ "${backup_filename_flag}" != 'true' ]; then
    terminate "Please specify backup filename (--backup NAME)"
  fi
}

#======================================================================================================================
# Defines the target versions for Docker and Docker Compose. See detect_available_versions() and
# validate_available_versions() for additional information.
#======================================================================================================================
# Globals:
#   - target_compose_version
#   - target_docker_version
#   - skip_docker_update
#   - skip_compose_update
#======================================================================================================================
define_target_version() {
  detect_available_versions
  [ "${skip_docker_update}" = 'false' ] && echo "Target Docker version: ${target_docker_version:-Unknown}"
  [ "${skip_compose_update}" = 'false' ] && echo "Target Docker Compose version: ${target_compose_version:-Unknown}"
  validate_available_versions
}

#======================================================================================================================
# Identifies the version of a downloaded Docker archive. See detect_available_downloads() for additional
# information.
#======================================================================================================================
# Globals:
#   - target_docker_version
#   - skip_docker_update
#   - skip_compose_update
#======================================================================================================================
define_target_download() {
  detect_available_downloads
  [ "${skip_docker_update}" = 'false' ] && echo "Target Docker version: ${target_docker_version:-Unknown}"
  [ "${skip_compose_update}" = 'false' ] && echo "Target Docker Compose version: Unknown"
  validate_downloaded_versions
}

#======================================================================================================================
# Prompts the user to confirm the operation, unless forced.
#======================================================================================================================
# Globals:
#   - force
#   - skip_docker_update
#   - skip_compose_update
#   - skip_driver_update
# Outputs:
#   Terminates with zero exit code if user does not confirm the operation.
#======================================================================================================================
confirm_operation() {
  if [ "${force}" != 'true' ] ; then
    echo
    echo "WARNING! This will replace:"
    [ "${skip_docker_update}" = "false" ]  && echo "  - Docker Engine"
    [ "${skip_compose_update}" = "false" ] && echo "  - Docker Compose"
    [ "${skip_driver_update}" = "false" ]  && echo "  - Docker daemon log driver"
    echo

    while true; do
      printf "Are you sure you want to continue? [y/N] "
      read -r yn
      yn=$(echo "${yn}" | tr '[:upper:]' '[:lower:]')

      case "${yn}" in
        y | yes )     break;;
        n | no | "" ) exit;;
        * )           echo "Please answer y(es) or n(o)";;
      esac
    done
  fi
}

#======================================================================================================================
# Workflow Functions
#======================================================================================================================

#======================================================================================================================
# Recreates an empty temp folder.
#======================================================================================================================
# Globals:
#   - temp_dir
# Outputs:
#   An empty temp folder.
#======================================================================================================================
execute_prepare() {
  execute_clean 'silent'
  mkdir -p "${temp_dir}"
}

#======================================================================================================================
# Stops a running Docker daemon by invoking 'synoservicectl' or 'synopkg', unless 'stage' is set to true.
#======================================================================================================================
# Globals:
#   - stage
# Outputs:
#   Stopped Docker daemon, or a non-zero exit code if the stop failed or timed out.
#======================================================================================================================
execute_stop_syno() {
  print_status "Stopping Docker service"

  if [ "${stage}" = 'false' ] ; then
    case "${dsm_major_version}" in
      "6")
        syno_status=$(synoservicectl --status "${SYNO_DOCKER_SERV_NAME}" | grep running -o)
        if [ "${syno_status}" = 'running' ] ; then
          timeout --foreground "${SYNO_SERVICE_STOP_TIMEOUT}" synoservicectl --stop "${SYNO_DOCKER_SERV_NAME}"
          syno_status=$(synoservicectl --status "${SYNO_DOCKER_SERV_NAME}" | grep stop -o)
          if [ "${syno_status}" != 'stop' ] ; then
            terminate "Could not stop Docker daemon"
          fi
        fi
        ;;
      "7")
        syno_status=$(synopkg status "${SYNO_DOCKER_SERV_NAME}" | grep started -o)
        if [ "${syno_status}" = 'started' ] ; then
          timeout --foreground "${SYNO_SERVICE_STOP_TIMEOUT}" synopkg stop "${SYNO_DOCKER_SERV_NAME}"
          syno_status=$(synopkg status "${SYNO_DOCKER_SERV_NAME}" | grep stopped -o)
          if [ "${syno_status}" != 'stopped' ] ; then
            terminate "Could not stop Docker daemon"
          fi
        fi
        ;;
      *)
        echo "ERROR: Cannot stop Docker package, unsupported DSM version: ${dsm_major_version}"
    esac
  else
    echo "Skipping Docker service control in STAGE mode"
  fi
}

#======================================================================================================================
# Creates a backup of the current Docker binaries (including Docker Compose), Docker daemon configuration, and
# the 'start-stop-status' script.
#======================================================================================================================
# Globals:
#   - backup_dir
#   - docker_backup_filename
# Outputs:
#   A backup archive.
#======================================================================================================================
execute_backup() {
  print_status "Backing up current Docker binaries (${backup_dir}/${docker_backup_filename})"
  cd "${backup_dir}" || terminate "Backup directory does not exist"
  tar -czvf "${docker_backup_filename}" -C "$SYNO_DOCKER_BIN_PATH" bin -C "$SYNO_DOCKER_JSON_PATH" "dockerd.json" \
    -C "${SYNO_DOCKER_SCRIPT_PATH}" "start-stop-status"
  if [ ! -f "${docker_backup_filename}" ] ; then
    terminate "Backup issue"
  fi
}

#======================================================================================================================
# Downloads the targeted Docker binary archive, unless instructed to skip the download.
#======================================================================================================================
# Globals:
#   - download_dir
#   - skip_docker_update
#   - target_docker_version
# Outputs:
#   A downloaded Docker binaries archive, or a non-zero exit code if the download has failed.
#======================================================================================================================
execute_download_bin() {
  if [ "${skip_docker_update}" = 'false' ] ; then
    target_docker_bin="docker-${target_docker_version}.tgz"
    print_status "Downloading target Docker binary (${DOWNLOAD_DOCKER}/${target_docker_bin})"
    response=$(curl "${DOWNLOAD_DOCKER}/$target_docker_bin" --write-out '%{http_code}' \
      -o "${download_dir}/${target_docker_bin}")
    if [ "${response}" != 200 ] ; then
      terminate "Binary could not be downloaded"
    fi
  fi
}

#======================================================================================================================
# Extracts a downloaded Docker binaries archive in the temp folder, unless instructed to skip the update.
#======================================================================================================================
# Globals:
#   - download_dir
#   - skip_docker_update
#   - target_docker_version
#   - temp_dir
# Outputs:
#   An extracted Docker binaries archive, or a non-zero exit code if the extraction has failed.
#======================================================================================================================
execute_extract_bin() {
  if [ "${skip_docker_update}" = 'false' ] ; then
    target_docker_bin="docker-${target_docker_version}.tgz"
    print_status "Extracting target Docker binary (${download_dir}/${target_docker_bin})"

    if [ ! -f "${download_dir}/${target_docker_bin}" ] ; then
      terminate "Docker binary archive not found"
    fi

    cd "${temp_dir}" || terminate "Temp directory does not exist"
    tar -zxvf "${download_dir}/${target_docker_bin}"
    if [ ! -d "docker" ] ; then
      terminate "Files could not be extracted from archive"
    fi

    # override runc binary on Kernels 5+ is present
    if uname -r | grep -q '^5\.'; then
      print_status "Detected Kernel v5, downloading / pinning runc version."
      response=$(curl -L "${PINNED_RUNC}" --write-out '%{http_code}' -o "${temp_dir}/docker/runc")
      if [ "${response}" != 200 ] ; then
        terminate "runc binary could not be downloaded"
      fi
      chmod +x "${temp_dir}/docker/runc"
    fi
  fi
}

# TODO: fix
#======================================================================================================================
# Extracts a Docker binaries backup archive in the temp folder.
#======================================================================================================================
# Globals:
#   - backup_dir
#   - docker_backup_filename
#   - temp_dir
# Outputs:
#   An extracted Docker binaries archive, or a non-zero exit code if expected files are not present in the backup.
#======================================================================================================================
execute_extract_backup() {
  print_status "Extracting Docker backup (${backup_dir}/${docker_backup_filename})"

  if [ ! -f "${backup_dir}/${docker_backup_filename}" ] ; then
    terminate "Backup file not found"
  fi

  cd "${temp_dir}" || terminate "Temp directory does not exist"
  tar -zxvf "${backup_dir}/${docker_backup_filename}"
  mv bin docker

  if [ ! -d "docker" ] ; then
    terminate "Docker binaries could not be extracted from archive"
  fi
  if [ ! -f "docker/docker-compose" ] ; then
    terminate "Docker compose binary could not be extracted from archive"
  fi
  if [ ! -f "dockerd.json" ] ; then
    terminate "Log driver configuration could not be extracted from archive"
  fi
}

#======================================================================================================================
# Downloads the targeted Docker Compose binary, unless instructed to skip the download. As the download path has
# changed since release of Docker Compose v2, this function checks the major version of the target binary and updates
# the path accordingly.
#======================================================================================================================
# Globals:
#   - download_dir
#   - skip_compose_update
#   - target_compose_version
# Outputs:
#   A downloaded Docker Compose binary, or a non-zero exit code if the download has failed.
#======================================================================================================================
execute_download_compose() {
  if [ "${skip_compose_update}" = 'false' ] ; then
    major_compose=$(echo "${target_compose_version}" | cut -d "." -f1)
    base_path="${DOWNLOAD_GITHUB}/releases/download"
    # as of version 2, the download path uses a 'v' prefix and is in lower case
    compose_bin="${base_path}/v${target_compose_version}/docker-compose-linux-${CPU_ARCH}"
    if [ "${major_compose}" -lt 2 ] ; then
      # below version 2, the download path does not use a 'v' prefix and uses sentence case for the platform
      compose_bin="${base_path}/${target_compose_version}/docker-compose-Linux-${CPU_ARCH}"
    fi

    print_status "Downloading target Docker Compose binary (${compose_bin})"
    response=$(curl -L "${compose_bin}" --write-out '%{http_code}' -o "${download_dir}/docker-compose")
    if [ "${response}" != 200 ] ; then
      terminate "Binary could not be downloaded"
    fi
  fi
}

#======================================================================================================================
# Install the Docker and Docker Compose binaries, unless instructed to skip installation or when 'stage' is set to
# true.
#======================================================================================================================
# Globals:
#   - download_dir
#   - skip_compose_update
#   - skip_docker_update
#   - stage
#   - temp_dir
# Outputs:
#   Installed Docker and Docker Compose binaries.
#======================================================================================================================
execute_install_bin() {
  print_status "Installing binaries"
  if [ "${stage}" = 'false' ] ; then
    if [ "${skip_docker_update}" = 'false' ] ; then
      cp "${temp_dir}"/docker/* "${SYNO_DOCKER_BIN}"/
    fi
    if [ "${skip_compose_update}" = 'false' ] ; then
      cp "${download_dir}"/docker-compose "${SYNO_DOCKER_BIN}"/docker-compose
    fi
    chown root:root "${SYNO_DOCKER_BIN}"/*
    chmod +x "${SYNO_DOCKER_BIN}"/*
    mkdir -p /var/lib/docker/volumes  # creates folder to improve compatability for some containers
  else
    echo "Skipping installation in STAGE mode"
  fi
}

#======================================================================================================================
# Restores the Docker and Docker Compose binaries extracted from a backup archive, unless 'stage' is set to true.
#======================================================================================================================
# Globals:
#   - stage
#   - temp_dir
#   - skip_docker_update
#   - skip_compose_update
# Outputs:
#   Restored Docker and Docker Compose binaries.
#======================================================================================================================
# TODO: validate this function
execute_restore_bin() {
  print_status "Restoring binaries"
  if [ "${stage}" = 'false' ] ; then
    if [ "${skip_docker_update}" = 'true' ] && [ "${skip_compose_update}" = 'true' ] ; then
      echo "Skipping restore of binaries"
    fi
    # copy Docker Engine binaries
    if [ "${skip_docker_update}" = 'false' ] ; then
      find "${temp_dir}"/docker/ -type f \( ! -name docker-compose \) -print -exec cp -rpf '{}' "${SYNO_DOCKER_BIN}"/ ";"
    fi
    # copy Docker Compose
    if [ "${skip_compose_update}" = 'false' ] ; then
      cp "${temp_dir}"/docker/docker-compose "${SYNO_DOCKER_BIN}"/
    fi
    chown root:root "${SYNO_DOCKER_BIN}"/*
    chmod +x "${SYNO_DOCKER_BIN}"/*
  else
    echo "Skipping restore in STAGE mode"
  fi
}

#======================================================================================================================
# Updates the log driver of the Docker daemon, unless 'stage' is set to true.
#======================================================================================================================
# Globals:
#   - stage
#   - skip_driver_update
# Outputs:
#   Updated Docker daemon configuration.
#======================================================================================================================
execute_update_log() {
  print_status "Configuring log driver"
  if [ "${stage}" = 'false' ] && [ "${skip_driver_update}" = 'false' ] ; then
    "${SCRIPT_DIR}/syno_docker_switch_logger.sh" "${SYNO_DOCKER_JSON}"
  else
    echo "Skipping configuration in STAGE mode or TARGET mode"
  fi
}

#======================================================================================================================
# Updates Synology's start-stop-status script for Docker to ensure IP forwarding is enabled, unless 'stage' is set to
# true.
#======================================================================================================================
# Globals:
#   - stage
# Outputs:
#   Updated start-stop-status script.
#======================================================================================================================
execute_update_script() {
  print_status "Enabling IP forwarding"
  if [ "${stage}" = 'false' ]; then
    # File to edit
    file="${SYNO_DOCKER_SCRIPT}"

    # Search and check conditions
    if ! grep -q 'iptables -P FORWARD ACCEPT' "${file}"; then
      match="^[[:space:]]*# start docker[[:space:]]*$"
      # Use sed to append the lines before the match
      sed -i "/${match}/i\\${SYNO_DOCKER_SCRIPT_FORWARDING}" "${file}"
      echo "Added missing IP forwarding configuration to ${file}."
    else
      echo "IP forwarding is already enabled in ${file}."
    fi
    # Ensure DOCKER-FORWARD jump rule is present (Docker v25+ compatibility)
    if ! grep -q 'DOCKER-FORWARD' "${file}"; then
      match="^[[:space:]]*iptables -P FORWARD ACCEPT"
      sed -i "/${match}/a\\          iptables -C FORWARD -j DOCKER-FORWARD 2>/dev/null || iptables -I FORWARD 1 -j DOCKER-FORWARD" "${file}"
      echo "Added DOCKER-FORWARD jump rule to ${file}."
    fi
  else
    echo "Skipping configuration in STAGE mode"
  fi
}

#======================================================================================================================
# Restores the Docker daemon log driver extracted from a backup archive, unless 'stage' is set to true.
#======================================================================================================================
# Globals:
#   - stage
#   - temp_dir
#   - skip_driver_update
# Outputs:
#   Updated Docker daemon configuration.
#======================================================================================================================
execute_restore_log() {
  print_status "Restoring log driver"
  if [ "${stage}" = 'false' ] && [ "${skip_driver_update}" = 'false' ] ; then
    cp "${temp_dir}"/dockerd.json "${SYNO_DOCKER_JSON}"
  else
    echo "Skipping restoring in STAGE mode or TARGET mode"
  fi
}

#======================================================================================================================
# Restores Synology's Docker start-stop-status script from a backup archive, unless 'stage' is set to true.
#======================================================================================================================
# Globals:
#   - stage
#   - temp_dir
# Outputs:
#   Updated start-stop-status script.
#======================================================================================================================
execute_restore_script() {
  print_status "Restoring start-stop-status script"
  if [ "${stage}" = 'false' ] ; then
    cp "${temp_dir}"/start-stop-status "${SYNO_DOCKER_SCRIPT}"
  else
    echo "Skipping restoring in STAGE mode or TARGET mode"
  fi
}

#======================================================================================================================
# Start the Docker daemon by invoking 'synoservicectl' or 'synopkg', unless 'stage' is set to true.
#======================================================================================================================
# Globals:
#   - force
#   - stage
# Outputs:
#   Started Docker daemon, or a non-zero exit code if the start failed or timed out.
#======================================================================================================================
execute_start_syno() {
  print_status "Starting Docker service - May take a while. "
  echo "   - timeout set to ${SYNO_SERVICE_START_TIMEOUT} based on ${RUNNING_CONTAINERS} active containers"

  if [ "${stage}" = 'false' ] ; then
    case "${dsm_major_version}" in
      "6")
        timeout --foreground "${SYNO_SERVICE_START_TIMEOUT}" synoservicectl --start "${SYNO_DOCKER_SERV_NAME}"

        syno_status=$(synoservicectl --status "${SYNO_DOCKER_SERV_NAME}" | grep running -o)
        if [ "${syno_status}" != 'running' ] ; then
          if [ "${force}" != 'true' ] ; then
            terminate "Could not bring Docker Engine back online"
          else
            echo "ERROR: Could not bring Docker Engine back online"
          fi
        fi
        ;;
      "7")
        timeout --foreground "${SYNO_SERVICE_START_TIMEOUT}" synopkg start "${SYNO_DOCKER_SERV_NAME}"

        syno_status=$(synopkg status "${SYNO_DOCKER_SERV_NAME}" | grep started -o)
        if [ "${syno_status}" != 'started' ] ; then
          if [ "${force}" != 'true' ] ; then
            terminate "Could not bring Docker Engine back online"
          else
            echo "ERROR: Could not bring Docker Engine back online"
          fi
        fi
        ;;
      *)
        echo "ERROR: Cannot start Docker package, unsupported DSM version: ${dsm_major_version}"
    esac
  else
    echo "Skipping Docker service control in STAGE mode"
  fi
}

#======================================================================================================================
# Installs kernel modules for v28+
#======================================================================================================================
# Globals:
#   - install_iptables_modules
# Outputs:
#   modules installed, start script modified (if necessary)
#======================================================================================================================
install_modules() {
  print_status "Checking for / Installing iptables modules."
  if [[ "${install_iptables_modules}" == 'true' ]]; then
  echo "   Based on this version of docker, we'll need to check for / install iptables modules..."
  ./install_iptables_modules.sh || terminate "Could not install iptables modules. Stopping."
  fi
}

#======================================================================================================================
# Removes the temp folder.
#======================================================================================================================
# Globals:
#   - temp_dir
# Arguments:
#   $1 - Silences any status messages if set to 'silent'
# Outputs:
#   Removed temp folder.
#======================================================================================================================
execute_clean() {
  if [ "$1" != 'silent' ] ; then
    print_status "Cleaning the temp folder"
  fi
  rm -rf "${temp_dir}"
}

#======================================================================================================================
# Main Script
#======================================================================================================================

#======================================================================================================================
# Entrypoint for the script. It initializes the environment variables, generates the DNS plugin configuration, and
# runs the certbot to issue/renew the certificate.
#======================================================================================================================
main() {
  # Show header
  echo "Update Docker Engine and Docker Compose on Synology to target version"
  echo

  # Test if script has root privileges, exit otherwise
  id=$(id -u)
  if [ "${id}" -ne 0 ]; then
    usage
    terminate "You need to be root to run this script"
  fi

  # Validate dependencies
  validate_dependencies

  # Process and validate command-line arguments
  while [ "$1" != "" ]; do
    case "$1" in
      -b | --backup )
        shift
        docker_backup_filename="$1"
        backup_filename_flag='true'
        validate_backup_filename "Filename not provided"
        ;;
      -c | --compose )
        shift
        target_compose_version="$1"
        validate_version_input "${target_compose_version}" "Unrecognized target Docker Compose version"
        ;;
      -d | --docker )
        shift
        target_docker_version="$1"
        validate_version_input "${target_docker_version}" "Unrecognized target Docker version"
        ;;
      -f | --force )
        force='true'
        ;;
      --skip-iptables )
        skip_iptables_modules='true'
        ;;
      -h | --help )
        usage
        exit
        ;;
      -p | --path )
        shift
        backup_dir="$1"
        validate_provided_backup_path "Path not specified" "Path not found" \
          "Path is equal to temp directory, please specify a different path"
        ;;
      -s | --stage )
        stage='true'
        ;;
      -t | --target )
        shift
        target="$1"
        validate_target "Invalid target"
        ;;
      backup | restore | update | logger | validate | only_script )
        command="$1"
        ;;
      download | install )
        command="$1"
        shift
        download_dir="$1"
        validate_provided_download_path "Path not specified" "Path not found"
        ;;
      * )
        usage
        terminate "Unrecognized parameter ($1)"
    esac
    shift
  done

  # Execute workflows
  case "${command}" in
    only_script )
      total_steps=1
      execute_update_script
      ;;
    backup )
      total_steps=3
      detect_current_versions
      execute_prepare
      execute_backup
      ;;
    download )
      total_steps=2
      detect_current_versions
      execute_prepare
      define_target_version
      execute_download_bin
      execute_download_compose
      ;;
    install )
      total_steps=8
      detect_current_versions
      execute_prepare
      define_target_download
      confirm_operation
      execute_backup
      install_modules
      execute_stop_syno
      execute_extract_bin
      execute_install_bin
      execute_update_log
      execute_update_script
      execute_start_syno
      ;;
    restore )
      total_steps=6
      detect_current_versions
      execute_prepare
      define_restore
      confirm_operation
      execute_extract_backup
      execute_stop_syno
      execute_restore_bin
      execute_restore_log
      execute_restore_script
      execute_start_syno
      ;;
    logger )
      total_steps=4
      detect_current_versions
      execute_prepare
      execute_stop_syno
      execute_backup
      execute_update_log
      execute_start_syno
      ;;
    update )
      total_steps=12
      detect_current_versions
      execute_prepare
      define_target_version
      define_update
      confirm_operation
      execute_backup
      install_modules
      execute_download_bin
      execute_download_compose
      execute_stop_syno
      execute_extract_bin
      execute_install_bin
      execute_update_log
      execute_update_script
      execute_start_syno
      execute_clean
      ;;
    validate )
      total_steps=3
      detect_current_versions
      define_target_version
      define_update
      ;;
    * )
      usage
      terminate "No command specified"
  esac

  echo "Done."
}

main "$@"