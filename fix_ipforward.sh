#!/bin/bash

# Test if script has root privileges, exit otherwise
id=$(id -u)
if [ "${id}" -ne 0 ]; then
  echo "You need to run this with sudo or as root."
  exit 1
fi

# Define the lines to insert
INSERT="            # Added by docker update\n          iptables -P FORWARD ACCEPT\n          iptables -C FORWARD -j DOCKER-FORWARD 2>/dev/null || iptables -I FORWARD 1 -j DOCKER-FORWARD"

# File to edit
file="/var/packages/ContainerManager/scripts/start-stop-status"

# Verify the insertion anchor exists before touching the file, so a missing anchor leaves
# the file unmodified.
match="^[[:space:]]*[$]DockerUpdaterBin postdaemonup[[:space:]]*$"
if ! grep -qE "${match}" "${file}"; then
  echo "WARNING: anchor '\$DockerUpdaterBin postdaemonup' not found in ${file}."
  echo "         File left unmodified -- check the file manually."
  exit 1
fi

# Remove any previously-inserted forwarding block, wherever it landed. Earlier versions inserted it
# before 'start_docker_daemon', where the DOCKER-FORWARD chain does not yet exist. The insmod block
# sharing the same comment is left untouched.
sed -i '/^[[:space:]]*iptables -C FORWARD -j DOCKER-FORWARD/d' "${file}"
sed -i '/^[[:space:]]*iptables -[ID] FORWARD -[io] docker0 -j ACCEPT[[:space:]]*$/d' "${file}"
sed -i '/^[[:space:]]*# Added by docker update[[:space:]]*$/{N;/\n[[:space:]]*iptables -P FORWARD ACCEPT/d}' "${file}"
sed -i '/^[[:space:]]*iptables -P FORWARD ACCEPT[[:space:]]*$/d' "${file}"

# Insert only after the daemon is confirmed up. dockerd creates the DOCKER-FORWARD chain, so the
# jump rule cannot be added any earlier.
sed -i "/${match}/i\\${INSERT}" "${file}"
echo "Added IP forwarding configuration to ${file} (post daemon start)"
echo
echo "To avoid a restart of docker, adding the rules now. This should automatically apply"
echo " with the next docker restart"
iptables -P FORWARD ACCEPT
iptables -C FORWARD -j DOCKER-FORWARD 2>/dev/null || iptables -I FORWARD 1 -j DOCKER-FORWARD
