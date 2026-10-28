#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(dirname "$(realpath "$0")")
readonly SCRIPT_DIR
readonly NOT_COMPOSE="!---not_managed_by_compose---!"
readonly MAYBE_PORTAINER="!---maybe_managed_by_portainer---!"

# Store container information in an array.
# Stopped containers are included so containers stuck on the removed 'db'
# logger remain visible.
containers_info=()
while IFS= read -r c; do
  [ -n "$c" ] || continue
  container_info=$(docker inspect "$c" --format "{{.Name}} {{if index .Config.Labels \"com.docker.compose.project.config_files\"}}{{index .Config.Labels \"com.docker.compose.project.config_files\"}}{{else}}${NOT_COMPOSE}{{end}} {{.HostConfig.LogConfig.Type}}")
  container_info=${container_info#/}
  containers_info+=("$container_info")
done < <(docker ps -aq)

# Sort the array based on the second field (compose location)
sorted_containers_info=()
while IFS= read -r info; do
  [ -n "$info" ] || continue
  sorted_containers_info+=("$info")
done < <(printf "%s\n" "${containers_info[@]}" | sort -t " " -k 2)
# Original with -u - this unfortunately hides portainer containers.
# IFS=$'\n' sorted_containers_info=($(printf "%s\n" "${containers_info[@]}" | sort -t -u " " -k 2))

# Calculate the maximum length for the container names and compose locations
max_container_length=0
max_location_length=0
max_logger_length=7
for info in "${sorted_containers_info[@]}"; do
  container=${info%% *}
  logger=${info##* }
  location=${info#* }
  location=${location% *}
  [ "${#container}" -gt "$max_container_length" ] && max_container_length=${#container}
  [ "${#location}" -gt "$max_location_length" ] && max_location_length=${#location}
  [ "${#logger}" -gt "$max_logger_length" ] && max_logger_length=${#logger}
done

# Print the header
echo
printf "%-${max_container_length}s  %-${max_location_length}s %-${max_logger_length}s\n" \
  "Container" "Compose_Location" "Logger"
printf "%-${max_container_length}s  %-${max_location_length}s %-${max_logger_length}s\n" \
  "$(printf '%*s' "${max_container_length}" '' | tr ' ' '-')" \
  "$(printf '%*s' "${max_location_length}" '' | tr ' ' '-')" \
  "$(printf '%*s' "${max_logger_length}" '' | tr ' ' '-')"

docker_managed=()
# Print the sorted container information
for info in "${sorted_containers_info[@]}"; do
  container=${info%% *}
  logger=${info##* }
  location=${info#* }
  location=${location% *}
  raw_location=$location
  if [ "$location" != "$NOT_COMPOSE" ] && [ ! -f "$location" ];then
  location="${MAYBE_PORTAINER}"
  fi
  if [ "$raw_location" == "$NOT_COMPOSE" ]; then
  docker_managed+=("$container")
  fi
  printf "%-${max_container_length}s  %-${max_location_length}s %s\n" "$container" "$location" "$logger"
done

if [ ${#docker_managed[@]} -gt 0 ]; then
  # There are containers not managed by compose nor portainer.
  # Provide some clues on how to restart those containers.
  echo
  echo "The following containers may have been created with docker commands."
  echo "Below are some clues on the command needed to to recreate them ONLY IF YOU HAVE NO OTHER WAY TO DO SO."
  echo "...this is a best guess and may not be 100% accurate."
  echo "If these containers already show as 'local' logger, there is no need to recreate them manually"
  echo
  for container in "${docker_managed[@]}"; do
    docker_command=$("${SCRIPT_DIR}/container_recreate.sh" "$container")
    echo "----------------------------------------------------"
    echo "Container: ${container}"
    echo "----------------------------------------------------"
    printf '%s\n' "$docker_command"
    echo
  done
fi
