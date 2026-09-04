#!/bin/bash

# Test if script has root privileges, exit otherwise
id=$(id -u)
if [ "${id}" -ne 0 ]; then
  echo "You need to run this with sudo or as root."
  exit 1
fi

# Define the lines to insert
FORWARD_ACCEPT="            # Added by docker update\n          iptables -P FORWARD ACCEPT\n          iptables -C FORWARD -j DOCKER-FORWARD 2>/dev/null || iptables -I FORWARD 1 -j DOCKER-FORWARD"
DOCKER_FORWARD="            # Added by docker update\n          iptables -I FORWARD -i docker0 -j ACCEPT\n          iptables -I FORWARD -o docker0 -j ACCEPT\n          iptables -C FORWARD -j DOCKER-FORWARD 2>/dev/null || iptables -I FORWARD 1 -j DOCKER-FORWARD"

# File to edit
file="/var/packages/ContainerManager/scripts/start-stop-status"

# Determine the current mode before removing anything
if grep -q 'iptables -P FORWARD ACCEPT' "${file}"; then
  mode="accept"
elif grep -q 'iptables -I FORWARD -i docker0 -j ACCEPT' "${file}"; then
  mode="docker0"
else
  echo "No IP FORWARD rules found in ${file}."
  exit 0
fi

# Verify the insertion anchor exists before touching the file, so a missing anchor leaves
# the file unmodified. dockerd creates the DOCKER-FORWARD chain, so the jump rule cannot be
# added any earlier than this anchor.
match="^[[:space:]]*[$]DockerUpdaterBin postdaemonup[[:space:]]*$"
if ! grep -qE "${match}" "${file}"; then
  echo "WARNING: anchor '\$DockerUpdaterBin postdaemonup' not found in ${file}."
  echo "         File left unmodified -- check the file manually."
  exit 1
fi

# Remove the existing forwarding block, wherever it landed. Earlier versions inserted it before
# 'start_docker_daemon', where the DOCKER-FORWARD chain does not yet exist. The insmod block
# sharing the same comment is left untouched.
sed -i '/^[[:space:]]*iptables -C FORWARD -j DOCKER-FORWARD/d' "${file}"
sed -i '/^[[:space:]]*# Added by docker update[[:space:]]*$/{N;/\n[[:space:]]*iptables -P FORWARD ACCEPT/d}' "${file}"
sed -i '/^[[:space:]]*# Added by docker update[[:space:]]*$/{N;/\n[[:space:]]*iptables -I FORWARD -i docker0/d}' "${file}"
sed -i '/^[[:space:]]*iptables -[ID] FORWARD -[io] docker0 -j ACCEPT[[:space:]]*$/d' "${file}"
sed -i '/^[[:space:]]*iptables -P FORWARD ACCEPT[[:space:]]*$/d' "${file}"

if [ "${mode}" = "accept" ]; then
  echo "Found FORWARD ACCEPT policy in start-stop-status script..."
  echo "Switching to docker FORWARD rules"
  sed -i "/${match}/i\\${DOCKER_FORWARD}" "${file}"
  echo "Replaced FORWARD ACCEPT policy with docker FORWARD rules (post daemon start)"
  echo
  echo "To avoid a restart of docker, applying the rules now. This should automatically apply"
  echo " with the next docker restart"
  iptables -I FORWARD -i docker0 -j ACCEPT
  iptables -I FORWARD -o docker0 -j ACCEPT
  iptables -C FORWARD -j DOCKER-FORWARD 2>/dev/null || iptables -I FORWARD 1 -j DOCKER-FORWARD
else
  echo "Found FORWARD rules for docker interface in start-stop-status script..."
  echo "Switching to FORWARD ACCEPT policy"
  sed -i "/${match}/i\\${FORWARD_ACCEPT}" "${file}"
  echo "Restored FORWARD ACCEPT policy (post daemon start)"
  echo
  echo "To avoid a restart of docker, applying the rules now. This should automatically apply"
  echo " with the next docker restart"
  # Remove the iptables rules that were previously inserted
  iptables -D FORWARD -i docker0 -j ACCEPT 2>/dev/null
  iptables -D FORWARD -o docker0 -j ACCEPT 2>/dev/null
  # Reset default policy
  iptables -P FORWARD ACCEPT
  iptables -C FORWARD -j DOCKER-FORWARD 2>/dev/null || iptables -I FORWARD 1 -j DOCKER-FORWARD
fi
