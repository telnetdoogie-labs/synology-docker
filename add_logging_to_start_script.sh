#!/bin/bash

# Warn user of usage, get confirmation
echo "WARNING! This should only be used on DSM 7.2.X, and is for troubleshooting only."
echo "It will add logging to your docker startup for troubleshooting purposes."
echo "While it will take a backup of your original startup script, you run it at your own risk."
echo " Do not run this script unless you have been instructed to do so for troubleshooting"
echo
while true; do
    echo "Are you SURE you want to continue? [y/N] "
    read -r yn
    yn=$(echo "${yn}" | tr '[:upper:]' '[:lower:]')
    case "${yn}" in
        y | yes )     break;;
        * ) exit;;
    esac
done

# Test if script has root privileges, exit otherwise
id=$(id -u)
if [ "${id}" -ne 0 ]; then
    echo
    echo "You need to be root to run this script. Run again with:"
    echo
    echo " sudo $0"
    exit
fi

# Backup original File
echo
echo "Backing up original file..."
echo
if [ -f "./start-stop-status.bkup" ]; then
  echo "Your start-stop-status script is already backed up as ./start-stop-status.bkup"
  echo "...skipping backup"
else
  cp /var/packages/ContainerManager/scripts/start-stop-status ./start-stop-status.bkup
fi
echo

if [ ! -f "./start-stop-status.bkup" ]; then
  echo
  echo "Problem backing up script. Stopping."
  exit
fi

# Move logging file to destination
echo "Replacing start-stop-status with logging-added version..."
cp -f ./test_file/start-stop-status.withlogging /var/packages/ContainerManager/scripts/start-stop-status
echo "Fix permissions on start-stop-status script..."
chmod 744 /var/packages/ContainerManager/scripts/start-stop-status
echo
echo "start-stop-status script replaced, logging added."
echo
echo "To observe logging during startup, run 'sudo cat /var/log/messages | grep Synology-Docker'"
echo