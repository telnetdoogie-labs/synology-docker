#!/bin/bash

# Test if script has root privileges, exit otherwise
id=$(id -u)
if [ "${id}" -ne 0 ]; then
  echo "You need to run this with sudo or as root."
  exit 1
fi

# Define the lines to insert
FORWARD_ACCEPT="        iptables -P FORWARD ACCEPT\n        iptables -C FORWARD -j DOCKER-FORWARD 2>/dev/null || iptables -I FORWARD 1 -j DOCKER-FORWARD"
DOCKER_FORWARD="        iptables -I FORWARD -i docker0 -j ACCEPT\n        iptables -I FORWARD -o docker0 -j ACCEPT\n        iptables -C FORWARD -j DOCKER-FORWARD 2>/dev/null || iptables -I FORWARD 1 -j DOCKER-FORWARD"

# File to edit
file="/var/packages/ContainerManager/scripts/start-stop-status"

if grep -q 'iptables -P FORWARD ACCEPT' "${file}"; then

  # this has the FORWARD ACCEPT rule in place.
  echo "Found FORWARD ACCEPT policy in start-stop-status script..."
  echo "Switching to docker FORWARD rules"
  match="^[[:space:]]*iptables -P FORWARD ACCEPT"
  # Use sed to replace the line with the DOCKER_FORWARD line
  sed -i "/${match}/c\\${DOCKER_FORWARD}" "${file}"
  echo "Modified FORWARD ACCEPT line with docker FORWARD rules"
  echo
  echo "To avoid a restart of docker, applying the rules now. This should automatically apply"
  echo "  with the next docker restart"
  iptables -I FORWARD -i docker0 -j ACCEPT
  iptables -I FORWARD -o docker0 -j ACCEPT
  iptables -C FORWARD -j DOCKER-FORWARD 2>/dev/null || iptables -I FORWARD 1 -j DOCKER-FORWARD

elif grep -q 'iptables -I FORWARD -i docker0 -j ACCEPT' "${file}"; then

  # this already has the DOCKER rules applied.
  echo "Found FORWARD rules for docker interface in start-stop-status script..."
  echo "Switching to FORWARD ACCEPT policy"
  match="^[[:space:]]*iptables -I FORWARD -i docker0 -j ACCEPT"
  # Use sed to replace docker0 lines with FORWARD ACCEPT.
  # Handle both old (2-line) and new (3-line, includes DOCKER-FORWARD guard) docker0 blocks.
  if grep -q 'DOCKER-FORWARD' "${file}"; then
    sed -i "/${match}/{N;N;s/.*\n.*\n.*/${FORWARD_ACCEPT}/}" "${file}"
  else
    sed -i "/${match}/{N;s/.*\n.*/${FORWARD_ACCEPT}/}" "${file}"
  fi
  echo "Restored FORWARD ACCEPT line"
  echo
  echo "To avoid a restart of docker, applying the rules now. This should automatically apply"
  echo "  with the next docker restart"
  # Remove the iptables rules that were previously inserted
  iptables -D FORWARD -i docker0 -j ACCEPT
  iptables -D FORWARD -o docker0 -j ACCEPT
  # Reset default policy
  iptables -P FORWARD ACCEPT
  iptables -C FORWARD -j DOCKER-FORWARD 2>/dev/null || iptables -I FORWARD 1 -j DOCKER-FORWARD

else
  echo "No IP FORWARD rules found in ${file}."
fi