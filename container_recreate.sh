#!/bin/bash
if [ "$2" == "debug" ] ; then
  readonly DEBUG=true
else
  readonly DEBUG=fale
fi

debug() {
  if [ "$DEBUG" == "true" ] ; then
    echo "DEBUG: $1"
  fi
}

# Check if a container ID or name was provided
if [ -z "$1" ]; then
  echo "Usage: $0 <container_name_or_id>"
  exit 1
fi

# Get container details using docker inspect
container_id=$1
container_info=$(docker inspect "$container_id") || { printf 'Error: Could not inspect container %s\n' "$container_id" >&2; exit 1; }

# Initialize an empty array for the docker command
docker_command=()

#echo" container name..."
# Extract the container name
container_name=$(printf '%s\n' "$container_info" | jq -r '.[0].Name // empty' | sed 's/\///')

debug "image name..."
# Extract the image name
image=$(printf '%s\n' "$container_info" | jq -r '.[0].Config.Image // empty')
if [ -z "$image" ]; then
  echo "Error: Image not found for container $container_id."
  exit 1
fi


# Extract environment variable names without exposing their values
env_vars=$(printf '%s\n' "$container_info" | jq -r '(.[0].Config.Env // [])[] | split("=")[0]' | sort -u)

debug "env variables..."
# Container environment values must be supplied in a reviewed environment file
has_env='false'
if [ -n "$env_vars" ]; then
  has_env='true'
fi

# Add base docker command to the array
docker_command=(docker run -d)

# Add name only if it exists
if [ -n "$container_name" ]; then
  docker_command+=(--name "$container_name")
fi

debug "environment variables (filtered)..."
# Format the remaining environment variables for docker run
if [ "$has_env" = 'true' ]; then
  docker_command+=(--env-file /REVIEW_AND_CREATE_ENV_FILE_BEFORE_RUNNING)
fi
docker_command+=(--log-driver local)

restart_policy=$(printf '%s\n' "$container_info" | jq -r '.[0].HostConfig.RestartPolicy.Name // empty')
restart_count=$(printf '%s\n' "$container_info" | jq -r '.[0].HostConfig.RestartPolicy.MaximumRetryCount // 0')
case "$restart_policy" in
  always|unless-stopped)
    docker_command+=(--restart "$restart_policy")
    ;;
  on-failure)
    if [ "$restart_count" -gt 0 ]; then
      docker_command+=(--restart "on-failure:$restart_count")
    else
      docker_command+=(--restart on-failure)
    fi
    ;;
esac

network_mode=$(printf '%s\n' "$container_info" | jq -r '.[0].HostConfig.NetworkMode // empty')
if [ -n "$network_mode" ] && [ "$network_mode" != 'default' ]; then
  docker_command+=(--network "$network_mode")
fi

entrypoint=$(printf '%s\n' "$container_info" | jq -r '.[0].Config.Entrypoint[0]? // empty')
if [ -n "$entrypoint" ]; then
  docker_command+=(--entrypoint "$entrypoint")
fi

debug "port mappings..."
# Extract port mappings and add each port to the array individually
ports=$(printf '%s\n' "$container_info" | jq -r '.[0].HostConfig.PortBindings // {} | to_entries[]? as $entry | $entry.value[]? | (.HostIp // "") as $host_ip | "-p " + (if $host_ip == "" then "" elif ($host_ip | contains(":")) then "[" + $host_ip + "]:" else $host_ip + ":" end) + (.HostPort // "") + ":" + $entry.key')
if [ -n "$ports" ]; then
  # Add each port as a separate entry
  while IFS= read -r port; do
    docker_command+=(-p "${port#-p }")
  done <<< "$ports"
fi

debug "volumes..."
# Extract volumes and add each volume to the array individually
volumes=$(printf '%s\n' "$container_info" | jq -r '(.[0].Mounts // [])[] | select(.Type != "tmpfs") | (.Mode // "") as $mode | (if .RW == false and ($mode | split(",") | index("ro")) == null then (if $mode == "" then "ro" else $mode + ",ro" end) else $mode end) as $options | "-v " + (if .Type == "volume" and (.Name // "") != "" then .Name else .Source end) + ":" + .Destination + (if $options == "" then "" else ":" + $options end)')
if [ -n "$volumes" ]; then
  # Add each volume as a separate entry
  while IFS= read -r volume; do
    docker_command+=(-v "${volume#-v }")
  done <<< "$volumes"
fi

tmpfs_mounts=$(printf '%s\n' "$container_info" | jq -r '(.[0].Mounts // [])[] | select(.Type == "tmpfs") | .Destination + (if .RW == false then ":ro" else "" end)')
if [ -n "$tmpfs_mounts" ]; then
  while IFS= read -r mount; do
    docker_command+=(--tmpfs "$mount")
  done <<< "$tmpfs_mounts"
fi

debug "cmd..."
# Extract the command used inside the container
# Add the image and command
if [ "$(printf '%s\n' "$container_info" | jq -r '.[0].Config.OpenStdin // false')" = 'true' ]; then
  docker_command+=(-i)
fi
if [ "$(printf '%s\n' "$container_info" | jq -r '.[0].Config.Tty // false')" = 'true' ]; then
  docker_command+=(-t)
fi
docker_command+=("$image")
if [ -n "$entrypoint" ]; then
  while IFS= read -r -d '' entrypoint_arg; do
    docker_command+=("$entrypoint_arg")
  done < <(printf '%s\n' "$container_info" | jq -j '.[0].Config.Entrypoint[1:][]? | . + "\u0000"')
fi
while IFS= read -r -d '' command_arg; do
  docker_command+=("$command_arg")
done < <(printf '%s\n' "$container_info" | jq -j '.[0].Config.Cmd[]? | . + "\u0000"')

# Output the final docker command with a backslash at the end of each line except the last
if [ "$has_env" = 'true' ]; then
  printf '%s\n' '# Create a reviewed env file with these variables before running; values are intentionally hidden:'
  while IFS= read -r var; do
    printf '#   %q\n' "$var"
  done <<< "$env_vars"
fi
for ((i = 0; i < ${#docker_command[@]}; i++)); do
  if [ "$i" -eq 0 ]; then
    printf '%q' "${docker_command[$i]}"
  else
    printf ' \\\n    %q' "${docker_command[$i]}"
  fi
done
printf '\n'
