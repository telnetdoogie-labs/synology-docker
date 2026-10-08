#!/bin/bash

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
  printf "${RED}${BOLD}%s${NC}\n" "ERROR: $1" >&2
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
    "install_apparmor_profile.sh"
    "install_iptables_modules.sh"
    "syno_docker_list_containers.sh"
    "syno_docker_switch_logger.sh")
  # Loop through each file in the array and check if it exists
  for file in "${DEPENDENT_FILES[@]}"; do
    if [[ ! -f "$SCRIPT_DIR/$file" ]]; then
      terminate "Error: Required file '$file' is missing in the script directory ($SCRIPT_DIR). You may need to do a git pull."
    fi
    if [[ "$file" != 'install_apparmor_profile.sh' && ! -x "$SCRIPT_DIR/$file" ]]; then
      terminate "Required file '$file' is not executable in $SCRIPT_DIR"
    fi
  done
}

#======================================================================================================================
# Constants
#======================================================================================================================
readonly RED='\e[31m' # Red color
readonly NC='\e[m' # No color / reset
readonly BOLD='\e[1m' # Bold font
SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
readonly SCRIPT_DIR
readonly CPU_ARCH='x86_64'
readonly DOWNLOAD_DOCKER="https://download.docker.com/linux/static/stable/${CPU_ARCH}"
readonly DOWNLOAD_GITHUB='https://github.com/docker/compose'
readonly PINNED_RUNC='https://github.com/opencontainers/runc/releases/download/v1.3.2/runc.amd64'
readonly GITHUB_API_COMPOSE='https://api.github.com/repos/docker/compose/releases/latest'
readonly UPDATE_CURL_HTTPS_FLAGS=(--proto '=https' --proto-redir '=https' --tlsv1.2)
curl_https_update() {
  curl "$@" "${UPDATE_CURL_HTTPS_FLAGS[@]}"
}
if [[ -d "/var/packages/ContainerManager" ]]; then
  readonly SYNO_DOCKER_DIR='/var/packages/ContainerManager'
  readonly SYNO_DOCKER_SERV_NAME='ContainerManager'
elif [[ -d "/var/packages/Docker" ]]; then
  readonly SYNO_DOCKER_DIR='/var/packages/Docker'
  readonly SYNO_DOCKER_SERV_NAME='Docker'
fi
if [[ -z "$SYNO_DOCKER_DIR" ]]; then
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
readonly SYNOPKG_BIN='/usr/syno/bin/synopkg'
readonly SYNOSERVICECTL_BIN='/usr/syno/sbin/synoservicectl'
if ! RUNNING_CONTAINERS=$(docker ps -q 2>/dev/null | awk 'NF' | wc -l); then
  RUNNING_CONTAINERS=0
fi
if [[ "$RUNNING_CONTAINERS" -gt 5 ]]; then
  computed_timeout=$(( (RUNNING_CONTAINERS * 3) / 2 ))
  if [[ "$computed_timeout" -lt 10 ]]; then
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
temp_dir=''
backup_dir="${PWD}"
download_dir=''
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
target_docker_explicit='false'
target_compose_explicit='false'
backup_filename_flag='false'
step=0
total_steps=0
install_iptables_modules='false'
skip_iptables_modules='false'
install_apparmor='false'
service_stopped='false'
preserve_stage='false'


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
  echo "  -s, --stage            Stage only; retain downloads without replacing binaries or configuration"
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
  echo "  only_script            Update ONLY the start-stop-status IP forwarding block (no binaries, no restart)"
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
  if [[ -z "${compose_version}" ]] ; then
    compose_version=$(docker-compose -v 2>/dev/null | grep -Eo "[0-9]*.[0-9]*.[0-9]*," | cut -d',' -f 1)
  fi

  containerd_version=$(containerd -version | grep -Eo "v[0-9]+.[0-9]+.[0-9]+" | cut -c 2-)
  runc_version=$(runc -version | grep -Eo "v[0-9]+.[0-9]+.[0-9]+" | cut -c 2-)

  echo "Current DSM version: ${dsm_version:-Unknown}"
  echo "Current Docker version: ${docker_version:-Unknown}"
  echo "Current Docker Compose version: ${compose_version:-Unknown}"
  echo "Current containerd version: ${containerd_version:-Unknown}"
  echo "Current runc version: ${runc_version:-Unknown}"

  if [[ "${force}" != 'true' ]] ; then
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
  if [[ "${current_arch}" != "${CPU_ARCH}" ]]; then
    terminate "This script supports ${CPU_ARCH} CPUs only, use --force to override"
  fi

  case "${dsm_major_version}" in
    6 | 7 ) ;;
    * ) terminate "This script supports DSM 6 and 7 only" ;;
  esac

  # Test Docker version is present, exit otherwise
  if [[ -z "${docker_version}" ]] && [[ "${skip_docker_update}" = 'false' ]] ; then
    terminate "Could not detect current Docker version, use --force to override"
  fi

  # Test Docker Compose version is present, exit otherwise
  if [[ -z "${compose_version}" ]] && [[ "${skip_compose_update}" = 'false' ]]; then
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
is_semver() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

version_is_newer() {
  local left_major left_minor left_patch right_major right_minor right_patch
  IFS=. read -r left_major left_minor left_patch <<< "$1"
  IFS=. read -r right_major right_minor right_patch <<< "$2"
  (( 10#$left_major > 10#$right_major ||
    (10#$left_major == 10#$right_major && 10#$left_minor > 10#$right_minor) ||
    (10#$left_major == 10#$right_major && 10#$left_minor == 10#$right_minor &&
      10#$left_patch > 10#$right_patch) ))
}

detect_available_downloads() {
  if [[ -z "${target_docker_version}" ]]; then
    for archive in "${download_dir}"/docker-*.tgz; do
      [[ -f "$archive" ]] || continue
      candidate=${archive##*/}
      candidate=${candidate#docker-}
      candidate=${candidate%.tgz}
      if is_semver "$candidate" && { [[ -z "$target_docker_version" ]] || version_is_newer "$candidate" "$target_docker_version"; }; then
        target_docker_version=$candidate
      fi
    done
  fi
}

#======================================================================================================================
# Detects latest stable versions of Docker and Docker Compose available for download. The detection is skipped if a
# specific target Docker and/or Compose version is already specified. Version lookup failures stop the operation.
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
  if [[ -z "${target_docker_version}" ]] && [[ "${skip_docker_update}" = 'false' ]]; then
    docker_index=$(curl_https_update -fsSL "${DOWNLOAD_DOCKER}/") || terminate "Could not query available Docker versions"
    docker_bin_files=$(printf '%s\n' "$docker_index" | grep -Eo '>docker-[0-9]+\.[0-9]+\.[0-9]+\.tgz' | cut -c 2-)
    while IFS= read -r docker_bin; do
      [[ -n "$docker_bin" ]] || continue
      candidate=${docker_bin#docker-}
      candidate=${candidate%.tgz}
      if [[ -z "$target_docker_version" ]] || version_is_newer "$candidate" "$target_docker_version"; then
        target_docker_version=$candidate
      fi
    done <<< "$docker_bin_files"
    [[ -n "$target_docker_version" ]] || terminate "Could not detect Docker versions available for download"
  fi

  # Detect latest available stable Docker Compose version (ignores release candidates)
  if [[ -z "${target_compose_version}" ]] && [[ "${skip_compose_update}" = 'false' ]]; then
    compose_release=$(curl_https_update -fsSL "${GITHUB_API_COMPOSE}") || terminate "Could not query available Docker Compose versions"
    target_compose_version=$(printf '%s\n' "$compose_release" | jq -er '.tag_name | ltrimstr("v")') || terminate "Could not detect Docker Compose version"
    is_semver "$target_compose_version" || terminate "Unrecognized available Docker Compose version: $target_compose_version"
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
  if [[ -z "${target_docker_version}" ]] && [[ "${skip_docker_update}" = 'false' ]] ; then
    terminate "Could not find Docker binaries for downloading"
  fi

  # Test Docker Compose is available for download, exit otherwise
  if [[ -z "${target_compose_version}" ]] && [[ "${skip_compose_update}" = 'false' ]] ; then
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
  if [[ ! -f "${download_dir}/${target_docker_bin}" ]] && [[ "${skip_docker_update}" = 'false' ]] ; then
    terminate "Could not find Docker archive (${download_dir}/${target_docker_bin})"
  fi

  # Test Docker-compose binary is available on path
  if [[ ! -f "${download_dir}/docker-compose" ]] && [[ "${skip_compose_update}" = 'false' ]] ; then
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
  if [[ "${validation}" != "$1" ]] ; then
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
  if [[ -z "${docker_backup_filename}" ]] || [[ "${prefix}" = "-" ]] ; then
    usage
    terminate "$1"
  fi

  # split into directory and filename if applicable
  # TODO: test
  basepath=$(dirname "${docker_backup_filename}")
  if [[ -z "${basepath}" ]] || [[ "${basepath}" != "." ]]; then
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
  if [[ -z "${download_dir}" ]] || [[ "${prefix}" = "-" ]] ; then
    usage
    terminate "$1"
  fi

  # cut trailing '/' and convert to absolute path
  download_dir=$(readlink -f "${download_dir}")

  # check PATH exists
  if [[ ! -d "${download_dir}" ]] ; then
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
  if [[ -z "${backup_dir}" ]] || [[ "${prefix}" = "-" ]] ; then
    usage
    terminate "$1"
  fi

  # cut trailing '/' and convert to absolute path
  backup_dir=$(readlink -f "${backup_dir}")

  # check PATH exists
  if [[ ! -d "${backup_dir}" ]] ; then
    usage
    terminate "$2"
  fi

  # confirm backup dir is different from temp dir
  if [[ "${backup_dir}" = "${temp_dir}" ]] ; then
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
  if [[ "${skip_docker_update}" = 'false' ]]; then
    if is_semver "$docker_version" && version_is_newer "$docker_version" "$target_docker_version" &&
      { [[ "$force" != 'true' ]] || [[ "$target_docker_explicit" != 'true' ]]; }; then
      terminate "Target Docker version is older than installed version; specify --docker VERSION --force to downgrade"
    fi
    if [[ "$force" != 'true' ]] && [[ "$docker_version" = "$target_docker_version" ]]; then
      skip_docker_update='true'
      total_steps=$((total_steps-1))
    fi
  fi
  if [[ "${skip_compose_update}" = 'false' ]]; then
    if is_semver "$compose_version" && version_is_newer "$compose_version" "$target_compose_version" &&
      { [[ "$force" != 'true' ]] || [[ "$target_compose_explicit" != 'true' ]]; }; then
      terminate "Target Docker Compose version is older than installed version; specify --compose VERSION --force to downgrade"
    fi
    if [[ "$force" != 'true' ]] && [[ "$compose_version" = "$target_compose_version" ]]; then
      skip_compose_update='true'
      total_steps=$((total_steps-1))
    fi
  fi
  if [[ "${skip_driver_update}" = 'false' ]] && [[ "$force" != 'true' ]]; then
    log_driver=$(jq -r '.["log-driver"] // empty' "${SYNO_DOCKER_JSON}") || terminate "Could not read Docker daemon configuration"
    if [[ "$log_driver" = 'local' ]]; then
      skip_driver_update='true'
      total_steps=$((total_steps-1))
    fi
  fi
  if [[ "$skip_docker_update" = 'true' ]] && [[ "$skip_compose_update" = 'true' ]] && [[ "$skip_driver_update" = 'true' ]]; then
    terminate_with_warning "Docker and Docker Compose are already on target versions"
  fi
}

prepare_engine_requirements() {
  if [[ "$skip_docker_update" = 'false' ]]; then
    major=${target_docker_version%%.*}
    if (( 10#$major >= 28 )) && [[ "$skip_iptables_modules" = 'false' ]]; then
      install_iptables_modules='true'
      total_steps=$((total_steps+1))
    fi
    if (( 10#$major >= 29 )); then
      install_apparmor='true'
      total_steps=$((total_steps+1))
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
  if [[ "${backup_filename_flag}" != 'true' ]]; then
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
  [[ "${skip_docker_update}" = 'false' ]] && echo "Target Docker version: ${target_docker_version:-Unknown}"
  [[ "${skip_compose_update}" = 'false' ]] && echo "Target Docker Compose version: ${target_compose_version:-Unknown}"
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
  [[ "${skip_docker_update}" = 'false' ]] && echo "Target Docker version: ${target_docker_version:-Unknown}"
  [[ "${skip_compose_update}" = 'false' ]] && echo "Target Docker Compose version: Unknown"
  validate_downloaded_versions
}

validate_offline_target() {
  if [[ "$skip_docker_update" = 'false' ]] && [[ "$force" != 'true' ]] && is_semver "$docker_version" &&
    version_is_newer "$docker_version" "$target_docker_version"; then
    terminate "Offline Docker archive is older than installed version; use --force to downgrade"
  fi
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
  if [[ "${force}" != 'true' ]] ; then
    echo
    echo "WARNING! This will replace:"
    [[ "${skip_docker_update}" = "false" ]]  && echo "  - Docker Engine"
    [[ "${skip_compose_update}" = "false" ]] && echo "  - Docker Compose"
    [[ "${skip_driver_update}" = "false" ]]  && echo "  - Docker daemon log driver"
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
# Resolves the absolute path to a Synology system control binary ('synopkg' or 'synoservicectl').
#======================================================================================================================
# Arguments:
#   $1 - Binary name (e.g. 'synopkg' or 'synoservicectl').
#   $2 - Well-known absolute path for this binary on DSM (e.g. '/usr/syno/bin/synopkg').
# Outputs:
#   Writes the resolved absolute path to stdout. Terminates with a non-zero exit code if the
#   binary cannot be found at the well-known path or on PATH - this commonly happens when the
#   script is run via 'sudo', whose default PATH does not include '/usr/syno/bin' or
#   '/usr/syno/sbin'.
#======================================================================================================================
resolve_syno_bin() {
  local bin_name="$1"
  local well_known_path="$2"

  if [[ -x "${well_known_path}" ]]; then
    echo "${well_known_path}"
  elif command -v "${bin_name}" >/dev/null 2>&1; then
    command -v "${bin_name}"
  else
    terminate "Could not find '${bin_name}' (checked '${well_known_path}' and PATH). Cannot control the ${SYNO_DOCKER_SERV_NAME} package. If running via 'sudo', ensure PATH includes '/usr/syno/bin' and '/usr/syno/sbin', e.g.: sudo env PATH=/usr/syno/bin:/usr/syno/sbin:\$PATH $0 ..."
  fi
}

#======================================================================================================================
# Fails fast if the Synology package-control tool needed to stop/start the Docker package ('synopkg' on DSM 7,
# 'synoservicectl' on DSM 6) is not resolvable - rather than only discovering this midway through a run, when
# execute_stop_syno/execute_start_syno are reached.
#======================================================================================================================
# Globals:
#   - dsm_major_version
#   - stage
# Outputs:
#   Terminates with a non-zero exit code if the required tool cannot be resolved, unless 'stage' is true.
#======================================================================================================================
validate_syno_tools() {
  if [[ "${stage}" = 'true' ]] ; then
    return
  fi

  case "${dsm_major_version}" in
    "6")
      resolve_syno_bin "synoservicectl" "${SYNOSERVICECTL_BIN}" >/dev/null
      ;;
    "7")
      resolve_syno_bin "synopkg" "${SYNOPKG_BIN}" >/dev/null
      ;;
    *)
      terminate "Unsupported DSM major version: ${dsm_major_version}"
      ;;
  esac
}

#======================================================================================================================
# Workflow Functions
#======================================================================================================================

#======================================================================================================================
# Creates a private temp folder for this run.
#======================================================================================================================
# Globals:
#   - temp_dir
# Outputs:
#   An empty private temp folder.
#======================================================================================================================
execute_prepare() {
  temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/docker_update.XXXXXX") || terminate "Could not create a private temp directory"
  if [[ -z "$download_dir" ]]; then
    download_dir=$temp_dir
  fi
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

  if [[ "${stage}" = 'false' ]] ; then
    service_stopped='true'
    case "${dsm_major_version}" in
      "6")
        synoservicectl_bin=$(resolve_syno_bin "synoservicectl" "${SYNOSERVICECTL_BIN}")
        syno_status=$("${synoservicectl_bin}" --status "${SYNO_DOCKER_SERV_NAME}" | grep running -o)
        if [[ "${syno_status}" = 'running' ]] ; then
          timeout --foreground "${SYNO_SERVICE_STOP_TIMEOUT}" "${synoservicectl_bin}" --stop "${SYNO_DOCKER_SERV_NAME}"
          syno_status=$("${synoservicectl_bin}" --status "${SYNO_DOCKER_SERV_NAME}" | grep stop -o)
          if [[ "${syno_status}" != 'stop' ]] ; then
            terminate "Could not stop Docker daemon"
          fi
        elif [[ "$("${synoservicectl_bin}" --status "${SYNO_DOCKER_SERV_NAME}" | grep stop -o)" != 'stop' ]]; then
          terminate "Could not determine Docker daemon status"
        fi
        ;;
      "7")
        synopkg_bin=$(resolve_syno_bin "synopkg" "${SYNOPKG_BIN}")
        syno_status=$("${synopkg_bin}" status "${SYNO_DOCKER_SERV_NAME}" | grep started -o)
        if [[ "${syno_status}" = 'started' ]] ; then
          timeout --foreground "${SYNO_SERVICE_STOP_TIMEOUT}" "${synopkg_bin}" stop "${SYNO_DOCKER_SERV_NAME}"
          syno_status=$("${synopkg_bin}" status "${SYNO_DOCKER_SERV_NAME}" | grep stopped -o)
          if [[ "${syno_status}" != 'stopped' ]] ; then
            terminate "Could not stop Docker daemon"
          fi
        elif [[ "$("${synopkg_bin}" status "${SYNO_DOCKER_SERV_NAME}" | grep stopped -o)" != 'stopped' ]]; then
          terminate "Could not determine Docker daemon status"
        fi
        ;;
      *)
        terminate "Cannot stop Docker package on unsupported DSM version: ${dsm_major_version}"
        ;;
    esac
  else
    echo "Skipping Docker service control in STAGE mode"
  fi
}

#======================================================================================================================
# Creates a backup of the current Docker binaries (including Docker Compose), Docker daemon configuration, and
# the 'start-stop-status' script and any managed AppArmor profile.
#======================================================================================================================
# Globals:
#   - backup_dir
#   - docker_backup_filename
# Outputs:
#   A backup archive.
#======================================================================================================================
execute_backup() {
  local backup_file backup_temp
  local -a backup_sources
  backup_file="${backup_dir}/${docker_backup_filename}"
  print_status "Backing up current Docker binaries ($backup_file)"
  [[ -d "$backup_dir" ]] || terminate "Backup directory does not exist"
  if [[ -e "$backup_file" ]] || [[ -L "$backup_file" ]]; then
    terminate "Backup already exists: $backup_file"
  fi
  backup_sources=(-C "$SYNO_DOCKER_BIN_PATH" bin -C "$SYNO_DOCKER_JSON_PATH" dockerd.json
    -C "$SYNO_DOCKER_SCRIPT_PATH" start-stop-status)
  if [[ -f "${SYNO_DOCKER_JSON_PATH}/docker-default.profile.synology-docker-managed" ]]; then
    [[ -f "${SYNO_DOCKER_JSON_PATH}/docker-default.profile" ]] || terminate "Managed AppArmor profile is missing"
    backup_sources+=(-C "$SYNO_DOCKER_JSON_PATH" docker-default.profile docker-default.profile.synology-docker-managed)
  fi
  backup_temp=$(mktemp "${backup_file}.XXXXXX") || terminate "Could not create temporary backup"
  if ! tar -czvf "$backup_temp" "${backup_sources[@]}" || ! tar -tzf "$backup_temp" >/dev/null; then
    rm -f "$backup_temp"
    terminate "Could not create a complete Docker backup"
  fi
  if ! mv "$backup_temp" "$backup_file"; then
    rm -f "$backup_temp"
    terminate "Could not finalize Docker backup"
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
  if [[ "${skip_docker_update}" = 'false' ]] ; then
    target_docker_bin="docker-${target_docker_version}.tgz"
    print_status "Downloading target Docker binary (${DOWNLOAD_DOCKER}/${target_docker_bin})"
    response=$(curl_https_update "${DOWNLOAD_DOCKER}/$target_docker_bin" --write-out '%{http_code}' \
      -o "${download_dir}/${target_docker_bin}")
    if [[ "${response}" != 200 ]] ; then
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
  if [[ "${skip_docker_update}" = 'false' ]] ; then
    target_docker_bin="docker-${target_docker_version}.tgz"
    print_status "Extracting target Docker binary (${download_dir}/${target_docker_bin})"

    if [[ ! -f "${download_dir}/${target_docker_bin}" ]] ; then
      terminate "Docker binary archive not found"
    fi

    cd "${temp_dir}" || terminate "Temp directory does not exist"
    tar -zxvf "${download_dir}/${target_docker_bin}" || terminate "Could not extract Docker archive"
    if [[ ! -f "docker/docker" ]] || [[ ! -f "docker/dockerd" ]]; then
      terminate "Docker binaries could not be extracted from archive"
    fi

    # override runc binary on Kernels 5+ is present
    if uname -r | grep -q '^5\.'; then
      print_status "Detected Kernel v5, downloading / pinning runc version."
      response=$(curl_https_update -L "${PINNED_RUNC}" --write-out '%{http_code}' -o "${temp_dir}/docker/runc")
      if [[ "${response}" != 200 ]] ; then
        terminate "runc binary could not be downloaded"
      fi
      chmod +x "${temp_dir}/docker/runc" || terminate "Could not set runc executable permission"
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

  if [[ ! -f "${backup_dir}/${docker_backup_filename}" ]] ; then
    terminate "Backup file not found"
  fi

  cd "${temp_dir}" || terminate "Temp directory does not exist"
  tar -tzf "${backup_dir}/${docker_backup_filename}" >/dev/null || terminate "Backup archive is invalid"
  tar -zxvf "${backup_dir}/${docker_backup_filename}" || terminate "Could not extract Docker backup"
  mv bin docker || terminate "Docker binaries could not be extracted from archive"

  if [[ ! -d "docker" ]] ; then
    terminate "Docker binaries could not be extracted from archive"
  fi
  if [[ ! -f "docker/docker-compose" ]] ; then
    terminate "Docker compose binary could not be extracted from archive"
  fi
  if [[ ! -f "dockerd.json" ]] ; then
    terminate "Log driver configuration could not be extracted from archive"
  fi
  if [[ ! -f "start-stop-status" ]]; then
    terminate "Docker start-stop-status script could not be extracted from archive"
  fi
  if [[ -f "docker-default.profile.synology-docker-managed" ]] && [[ ! -f "docker-default.profile" ]]; then
    terminate "Managed AppArmor profile could not be extracted from archive"
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
  if [[ "${skip_compose_update}" = 'false' ]] ; then
    major_compose=$(echo "${target_compose_version}" | cut -d "." -f1)
    base_path="${DOWNLOAD_GITHUB}/releases/download"
    # as of version 2, the download path uses a 'v' prefix and is in lower case
    compose_bin="${base_path}/v${target_compose_version}/docker-compose-linux-${CPU_ARCH}"
    if [[ "${major_compose}" -lt 2 ]] ; then
      # below version 2, the download path does not use a 'v' prefix and uses sentence case for the platform
      compose_bin="${base_path}/${target_compose_version}/docker-compose-Linux-${CPU_ARCH}"
    fi

    print_status "Downloading target Docker Compose binary (${compose_bin})"
    response=$(curl_https_update -L "${compose_bin}" --write-out '%{http_code}' -o "${download_dir}/docker-compose")
    if [[ "${response}" != 200 ]] ; then
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
  if [[ "${stage}" = 'false' ]] ; then
    if [[ "$skip_docker_update" = 'true' ]] && [[ "$skip_compose_update" = 'true' ]]; then
      echo "Skipping binary installation in TARGET mode"
      return 0
    fi
    if [[ "${skip_docker_update}" = 'false' ]] ; then
      cp "${temp_dir}"/docker/* "${SYNO_DOCKER_BIN}"/ || terminate "Could not install Docker Engine binaries"
    fi
    if [[ "${skip_compose_update}" = 'false' ]] ; then
      cp "${download_dir}"/docker-compose "${SYNO_DOCKER_BIN}"/docker-compose || terminate "Could not install Docker Compose binary"
    fi
    chown root:root "${SYNO_DOCKER_BIN}"/* || terminate "Could not set Docker binary ownership"
    chmod +x "${SYNO_DOCKER_BIN}"/* || terminate "Could not set Docker binary permissions"
    mkdir -p /var/lib/docker/volumes || terminate "Could not create Docker volumes directory"  # creates folder to improve compatability for some containers
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
  if [[ "${stage}" = 'false' ]] ; then
    if [[ "${skip_docker_update}" = 'true' ]] && [[ "${skip_compose_update}" = 'true' ]] ; then
      echo "Skipping restore of binaries"
      return 0
    fi
    # copy Docker Engine binaries
    if [[ "${skip_docker_update}" = 'false' ]] ; then
      ( set -o pipefail
        find "${temp_dir}/docker" -type f ! -name docker-compose -print0 |
          while IFS= read -r -d '' binary; do
            cp -rpf "$binary" "${SYNO_DOCKER_BIN}/" || exit 1
          done
      ) || terminate "Could not restore Docker Engine binaries"
    fi
    # copy Docker Compose
    if [[ "${skip_compose_update}" = 'false' ]] ; then
      cp "${temp_dir}"/docker/docker-compose "${SYNO_DOCKER_BIN}"/ || terminate "Could not restore Docker Compose binary"
    fi
    chown root:root "${SYNO_DOCKER_BIN}"/* || terminate "Could not set Docker binary ownership"
    chmod +x "${SYNO_DOCKER_BIN}"/* || terminate "Could not set Docker binary permissions"
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
  if [[ "${stage}" = 'false' ]] && [[ "${skip_driver_update}" = 'false' ]] ; then
    "${SCRIPT_DIR}/syno_docker_switch_logger.sh" "${SYNO_DOCKER_JSON}" || terminate "Could not update Docker daemon log driver"
  else
    echo "Skipping configuration in STAGE mode or TARGET mode"
  fi
}

#======================================================================================================================
# Updates Synology's start-stop-status script for Docker to ensure IP forwarding is enabled, unless 'stage' is set to
# true.
#
# The forwarding block MUST be inserted after 'start_docker_daemon' has completed. The DOCKER-FORWARD chain is created
# by dockerd itself, so inserting the jump rule any earlier means 'iptables -C FORWARD -j DOCKER-FORWARD' fails (the
# chain does not exist) and the fallback 'iptables -I FORWARD 1 -j DOCKER-FORWARD' fails too. dockerd then sets the
# FORWARD policy to DROP, leaving a DROP policy with no jump - published container ports become unreachable from other
# hosts after every clean boot, while working again after any subsequent Container Manager restart (because dockerd
# already exists by then). That masking is what makes the bug look intermittent when it is actually deterministic.
#======================================================================================================================
# Globals:
#   - stage
# Outputs:
#   Updated start-stop-status script.
#======================================================================================================================
validate_forwarding_anchor() {
  if [[ "$command" != 'only_script' ]] && [[ "$skip_docker_update" = 'true' ]]; then
    return 0
  fi
  if [[ "$stage" = 'false' ]] && ! grep -qE '^[[:space:]]*[$]DockerUpdaterBin postdaemonup[[:space:]]*$' "$SYNO_DOCKER_SCRIPT"; then
    terminate "Cannot find Docker postdaemonup anchor in $SYNO_DOCKER_SCRIPT"
  fi
}

execute_update_script() {
  print_status "Enabling IP forwarding"
  if [[ "$command" != 'only_script' ]] && [[ "$skip_docker_update" = 'true' ]]; then
    echo "Skipping forwarding configuration in TARGET mode"
    return 0
  fi
  if [[ "${stage}" = 'false' ]]; then
    # File to edit
    local file match script_temp
    file="${SYNO_DOCKER_SCRIPT}"

    # Verify the insertion anchor exists before touching the file, so a missing anchor leaves
    # the file unmodified.
    match="^[[:space:]]*[$]DockerUpdaterBin postdaemonup[[:space:]]*$"
    validate_forwarding_anchor
    script_temp=$(mktemp "${file}.XXXXXX") || terminate "Could not create temporary Docker startup script"
    if ! cp -p "$file" "$script_temp"; then
      rm -f "$script_temp"
      terminate "Could not copy Docker startup script"
    fi
    # Remove any previously-inserted forwarding block, wherever it landed. Older versions of this script (and
    # fix_ipforward.sh / switch_forward.sh) inserted it before 'start_docker_daemon'. Only the iptables FORWARD lines
    # (and the comment directly above them) are removed; the identically-commented insmod block added by
    # install_iptables_modules.sh is left untouched.
    if ! sed -i '/^[[:space:]]*iptables -C FORWARD -j DOCKER-FORWARD/d' "$script_temp" ||
      ! sed -i '/^[[:space:]]*iptables -[ID] FORWARD -[io] docker0 -j ACCEPT[[:space:]]*$/d' "$script_temp" ||
      ! sed -i '/^[[:space:]]*# Added by docker update[[:space:]]*$/{N;/\n[[:space:]]*iptables -P FORWARD ACCEPT/d}' "$script_temp" ||
      ! sed -i '/^[[:space:]]*iptables -P FORWARD ACCEPT[[:space:]]*$/d' "$script_temp" ||
      ! sed -i "/${match}/i\\${SYNO_DOCKER_SCRIPT_FORWARDING}" "$script_temp" ||
      ! grep -q 'iptables -C FORWARD -j DOCKER-FORWARD' "$script_temp"; then
      rm -f "$script_temp"
      terminate "Could not update Docker startup script"
    fi

    # Insert only after the daemon is confirmed up.
    if ! mv "$script_temp" "$file"; then
      rm -f "$script_temp"
      terminate "Could not replace Docker startup script"
    fi
    echo "Added IP forwarding configuration to ${file} (post daemon start)."
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
  if [[ "${stage}" = 'false' ]] && [[ "${skip_driver_update}" = 'false' ]] ; then
    cp "${temp_dir}"/dockerd.json "${SYNO_DOCKER_JSON}" || terminate "Could not restore Docker daemon configuration"
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
  if [[ "${stage}" = 'false' ]] && [[ "${skip_docker_update}" = 'false' ]]; then
    cp "${temp_dir}"/start-stop-status "${SYNO_DOCKER_SCRIPT}" || terminate "Could not restore Docker start-stop-status script"
    if [[ -f "${SCRIPT_DIR}/install_apparmor_profile.sh" ]]; then
      if [[ -f "${temp_dir}/docker-default.profile.synology-docker-managed" ]]; then
        cp -p "${temp_dir}/docker-default.profile" "${SYNO_DOCKER_JSON_PATH}/docker-default.profile" || terminate "Could not restore managed AppArmor profile"
        cp -p "${temp_dir}/docker-default.profile.synology-docker-managed" "${SYNO_DOCKER_JSON_PATH}/docker-default.profile.synology-docker-managed" || terminate "Could not restore AppArmor ownership marker"
        bash "${SCRIPT_DIR}/install_apparmor_profile.sh" || terminate "Could not activate restored AppArmor profile"
      elif grep -q 'docker-default.profile' "${SYNO_DOCKER_SCRIPT}"; then
        bash "${SCRIPT_DIR}/install_apparmor_profile.sh" || terminate "Could not activate legacy AppArmor profile"
      else
        bash "${SCRIPT_DIR}/install_apparmor_profile.sh" --restore || terminate "Could not restore AppArmor configuration"
      fi
    fi
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

  if [[ "${stage}" = 'false' ]] ; then
    case "${dsm_major_version}" in
      "6")
        synoservicectl_bin=$(resolve_syno_bin "synoservicectl" "${SYNOSERVICECTL_BIN}")
        timeout --foreground "${SYNO_SERVICE_START_TIMEOUT}" "${synoservicectl_bin}" --start "${SYNO_DOCKER_SERV_NAME}"

        syno_status=$("${synoservicectl_bin}" --status "${SYNO_DOCKER_SERV_NAME}" | grep running -o)
        if [[ "${syno_status}" != 'running' ]]; then
          terminate "Could not bring Docker Engine back online"
        fi
        ;;
      "7")
        synopkg_bin=$(resolve_syno_bin "synopkg" "${SYNOPKG_BIN}")
        timeout --foreground "${SYNO_SERVICE_START_TIMEOUT}" "${synopkg_bin}" start "${SYNO_DOCKER_SERV_NAME}"

        syno_status=$("${synopkg_bin}" status "${SYNO_DOCKER_SERV_NAME}" | grep started -o)
        if [[ "${syno_status}" != 'started' ]]; then
          terminate "Could not bring Docker Engine back online"
        fi
        ;;
      *)
        terminate "Cannot start Docker package on unsupported DSM version: ${dsm_major_version}"
        ;;
    esac
    service_stopped='false'
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
  if [[ "${stage}" = 'true' ]]; then
    echo "Skipping module installation in STAGE mode"
    return
  fi
  print_status "Checking for / Installing iptables modules."
  if [[ "${install_iptables_modules}" == 'true' ]]; then
  echo "   Based on this version of docker, we'll need to check for / install iptables modules..."
  "${SCRIPT_DIR}/install_iptables_modules.sh" || terminate "Could not install iptables modules. Stopping."
  fi
}

#======================================================================================================================
# Installs apparmor_parser wrapper and docker-default AppArmor profile for v29+ (see install_apparmor_profile.sh)
#======================================================================================================================
# Globals:
#   - install_apparmor
# Outputs:
#   wrapper installed, profile installed and loaded, start script modified (if necessary)
#======================================================================================================================
install_apparmor_profile() {
  if [[ "${stage}" = 'true' ]]; then
    echo "Skipping AppArmor profile installation in STAGE mode"
    return
  fi
  if [[ "${install_apparmor}" == 'true' ]]; then
    print_status "Installing AppArmor parser wrapper and docker-default profile."
    bash "${SCRIPT_DIR}/install_apparmor_profile.sh" || terminate "Could not install AppArmor profile. Stopping."
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
  if [[ -n "$temp_dir" ]]; then
    if [[ "$1" != 'silent' ]]; then
      print_status "Cleaning the temp folder"
    fi
    rm -rf "$temp_dir" || terminate "Could not clean temporary files"
    temp_dir=''
  fi
}

cleanup_on_exit() {
  local status=$?
  if [[ "$status" -ne 0 ]] && [[ "$service_stopped" = 'true' ]]; then
    printf 'Docker service may be stopped. Backup: %s/%s\n' "$backup_dir" "$docker_backup_filename" >&2
  fi
  if [[ "$preserve_stage" != 'true' ]] && [[ -n "$temp_dir" ]]; then
    rm -rf "$temp_dir" || { printf 'Could not clean temporary files: %s\n' "$temp_dir" >&2; status=1; }
  fi
  return "$status"
}

#======================================================================================================================
# Main Script
#======================================================================================================================

#======================================================================================================================
# Entrypoint for the script. It validates the environment and arguments, then runs the selected Docker update,
# backup, download, restore, or validation workflow.
#======================================================================================================================
main() {
  # Show header
  echo "Update Docker Engine and Docker Compose on Synology to target version"
  echo

  # Test if script has root privileges, exit otherwise
  id=$(id -u)
  if [[ "${id}" -ne 0 ]]; then
    usage
    terminate "You need to be root to run this script"
  fi

  trap 'cleanup_on_exit' EXIT

  # Validate dependencies
  validate_dependencies

  # Process and validate command-line arguments
  while [[ "${1:-}" != "" ]]; do
    case "$1" in
      -b | --backup )
        shift
        docker_backup_filename="${1:-}"
        backup_filename_flag='true'
        validate_backup_filename "Filename not provided"
        ;;
      -c | --compose )
        shift
        target_compose_version="${1:-}"
        target_compose_explicit='true'
        validate_version_input "${target_compose_version}" "Unrecognized target Docker Compose version"
        ;;
      -d | --docker )
        shift
        target_docker_version="${1:-}"
        target_docker_explicit='true'
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
        backup_dir="${1:-}"
        validate_provided_backup_path "Path not specified" "Path not found" \
          "Path is equal to temp directory, please specify a different path"
        ;;
      -s | --stage )
        stage='true'
        ;;
      -t | --target )
        shift
        target="${1:-}"
        validate_target "Invalid target"
        ;;
      backup | restore | update | logger | validate | only_script )
        command="$1"
        ;;
      download | install )
        command="$1"
        shift
        download_dir="${1:-}"
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
      validate_syno_tools
      execute_prepare
      define_target_download
      validate_offline_target
      prepare_engine_requirements
      validate_forwarding_anchor
      confirm_operation
      execute_backup
      execute_extract_bin
      install_modules
      execute_stop_syno
      execute_install_bin
      execute_update_log
      execute_update_script
      install_apparmor_profile
      execute_start_syno
      if [[ "$stage" = 'true' ]]; then
        echo "Downloaded files remain at: $download_dir"
      fi
      ;;
    restore )
      total_steps=6
      detect_current_versions
      validate_syno_tools
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
      validate_syno_tools
      execute_prepare
      execute_backup
      execute_stop_syno
      execute_update_log
      execute_start_syno
      ;;
    update )
      total_steps=12
      detect_current_versions
      validate_syno_tools
      execute_prepare
      define_target_version
      define_update
      prepare_engine_requirements
      validate_forwarding_anchor
      confirm_operation
      execute_backup
      execute_download_bin
      execute_download_compose
      execute_extract_bin
      install_modules
      execute_stop_syno
      execute_install_bin
      execute_update_log
      execute_update_script
      install_apparmor_profile
      execute_start_syno
      if [[ "$stage" = 'true' ]]; then
        preserve_stage='true'
        echo "Staged files: $download_dir"
      else
        execute_clean 'status'
      fi
      ;;
    validate )
      total_steps=3
      detect_current_versions
      define_target_version
      define_update
      prepare_engine_requirements
      ;;
    * )
      usage
      terminate "No command specified"
  esac

  echo "Done."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
