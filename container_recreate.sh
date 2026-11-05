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

quote_arg() {
  printf '%q' "$1"
}

# Check if a container ID or name was provided
if [ -z "$1" ]; then
  echo "Usage: $0 <container_name_or_id>"
  exit 1
fi

# Get container details using docker inspect
container_id=$1
container_info=$(docker inspect "$container_id")

# Initialize an empty array for the docker command
docker_command=()

#echo" container name..."
# Extract the container name
container_name=$(echo "$container_info" | jq -r '.[0].Name // empty' | sed 's/\///')

debug "image name..."
# Extract the image name
image=$(echo "$container_info" | jq -r '.[0].Config.Image // empty')
if [ -z "$image" ]; then
  echo "Error: Image not found for container $container_id."
  exit 1
fi


# Extract host environment variables
host_env=$(printenv | awk -F= '{print $1}' | sort)

debug "env variables..."
# Extract container environment variables and filter out those present on the host - default to empty if no env vars
env_vars=$(echo "$container_info" | jq -r '(.[0].Config.Env // [])[]' | awk -F= '{print $1}' | sort)
filtered_env_vars=$(comm -23 <(echo "$env_vars") <(echo "$host_env"))

# Add base docker command to the array
docker_command+=("docker run -d \\")

# Add name only if it exists
if [ -n "$container_name" ]; then
  docker_command+=("--name $(quote_arg "$container_name")")
fi

debug "environment variables (filtered)..."
# Require an operator-supplied file rather than printing environment values.
if [ -n "$filtered_env_vars" ]; then
  docker_command+=("--env-file \"\${RECREATE_ENV_FILE:?Set RECREATE_ENV_FILE to a private env file}\"")
fi

debug "port mappings..."
# Extract port mappings and add each port to the array individually
while IFS= read -r -d '' port; do
  docker_command+=("-p $(quote_arg "$port")")
done < <(jq -j '.[0].HostConfig.PortBindings // {} | to_entries[]? | (.value[0].HostPort + ":" + .key + "\u0000")' <<< "$container_info")

debug "volumes..."
# Extract volumes and add each volume to the array individually
while IFS= read -r -d '' volume; do
  docker_command+=("-v $(quote_arg "$volume")")
done < <(jq -j '(.[0].Mounts // [])[] | (.Source + ":" + .Destination + "\u0000")' <<< "$container_info")

debug "cmd..."
# Extract the command used inside the container

# Add the image and command
docker_command+=("--log-driver local")
docker_line="-it $(quote_arg "$image")"
while IFS= read -r -d '' arg; do
  docker_line+=" $(quote_arg "$arg")"
done < <(jq -j '.[0].Config.Cmd[]? | . + "\u0000"' <<< "$container_info")
docker_command+=("$docker_line")

# Output the final docker command with a backslash at the end of each line except the last
if [ -n "$filtered_env_vars" ]; then
  echo '# Set RECREATE_ENV_FILE to a private file with the required environment values before running.'
fi
echo "${docker_command[0]}"
for ((i = 1; i < ${#docker_command[@]}; i++)); do
  if [ $i -lt $((${#docker_command[@]} - 1)) ]; then
    echo "    ${docker_command[$i]} \\"
  else
    echo "    ${docker_command[$i]}"
  fi
done
