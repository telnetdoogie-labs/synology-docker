#!/bin/bash

# Test if script has root privileges, exit otherwise
id=$(id -u)
if [ "${id}" -ne 0 ]; then
  echo "You need to run this with sudo or as root."
  exit 1
fi

# Define the lines to insert
INSERT="  # Added by docker update\n  iptables -P FORWARD ACCEPT\n  iptables -C FORWARD -j DOCKER-FORWARD 2>/dev/null || iptables -I FORWARD 1 -j DOCKER-FORWARD"

# File to edit
file="/var/packages/ContainerManager/scripts/start-stop-status"

# Search and check conditions
if ! grep -q 'iptables -P FORWARD ACCEPT' "${file}"; then
  match="^[[:space:]]*iptablestool --insmod"
  # Use sed to append the lines after the match
  sed -i "/${match}/a\\${INSERT}" "${file}"
  echo "Added missing IP forwarding configuration to ${file}"
  echo
  echo "To avoid a restart of docker, adding the rule now. This should automatically apply"
  echo "  with the next docker restart"
  iptables -P FORWARD ACCEPT
  iptables -C FORWARD -j DOCKER-FORWARD 2>/dev/null || iptables -I FORWARD 1 -j DOCKER-FORWARD
else
  echo "IP forwarding is already enabled in ${file}."
fi

# Ensure DOCKER-FORWARD jump rule is present (Docker v25+ compatibility)
if ! grep -q 'DOCKER-FORWARD' "${file}"; then
  match="^[[:space:]]*iptables -P FORWARD ACCEPT"
  sed -i "/${match}/a\\  iptables -C FORWARD -j DOCKER-FORWARD 2>/dev/null || iptables -I FORWARD 1 -j DOCKER-FORWARD" "${file}"
  echo "Added DOCKER-FORWARD jump rule to ${file}"
  echo
  echo "To avoid a restart of docker, adding the rule now. This should automatically apply"
  echo "  with the next docker restart"
  iptables -C FORWARD -j DOCKER-FORWARD 2>/dev/null || iptables -I FORWARD 1 -j DOCKER-FORWARD
fi