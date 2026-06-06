#!/bin/bash

# fix_apparmor.sh
# Adds "apparmor": false to dockerd.json to work around AppArmor startup
# failures on certain Synology DSM versions after a Docker/Container Manager update.
#
# Usage:
#   sudo ./fix_apparmor.sh          -- applies the fix
#   sudo ./fix_apparmor.sh --restore -- restores from backup

DOCKERD_JSON="/var/packages/ContainerManager/etc/dockerd.json"
BACKUP="./dockerd.json.bkup"

# ──────────────────────────────────────────────
# RESTORE MODE
# ──────────────────────────────────────────────
if [ "${1}" = "--restore" ]; then
    echo "Restore mode: restoring dockerd.json from backup..."
    echo

    if [ ! -f "${BACKUP}" ]; then
        echo "No backup found at ${BACKUP}. Nothing to restore."
        exit 1
    fi

    id=$(id -u)
    if [ "${id}" -ne 0 ]; then
        echo "You need to be root to run this script. Run again with:"
        echo
        echo "  sudo $0 --restore"
        exit 1
    fi

    cp "${BACKUP}" "${DOCKERD_JSON}"
    echo "Restored ${DOCKERD_JSON} from ${BACKUP}"
    echo
    echo "Restart Container Manager for the change to take effect:"
    echo
    echo "  sudo synopkg restart ContainerManager"
    exit 0
fi

# ──────────────────────────────────────────────
# APPLY MODE
# ──────────────────────────────────────────────
echo "WARNING! This script modifies your Docker daemon configuration."
echo "It adds 'apparmor: false' to dockerd.json to work around AppArmor"
echo "startup failures seen on some Synology systems after a Docker update."
echo "A backup of your current dockerd.json will be saved before any changes."
echo "Run with --restore to undo."
echo
while true; do
    echo "Are you SURE you want to continue? [y/N] "
    read -r yn
    yn=$(echo "${yn}" | tr '[:upper:]' '[:lower:]')
    case "${yn}" in
        y | yes ) break;;
        * ) exit;;
    esac
done

# Root check
id=$(id -u)
if [ "${id}" -ne 0 ]; then
    echo
    echo "You need to be root to run this script. Run again with:"
    echo
    echo "  sudo $0"
    exit 1
fi

# Check dockerd.json exists
if [ ! -f "${DOCKERD_JSON}" ]; then
    echo
    echo "Could not find ${DOCKERD_JSON}."
    echo "If you're on an older DSM with the Docker package (not Container Manager), try:"
    echo "  DOCKERD_JSON=/var/packages/Docker/etc/dockerd.json sudo $0"
    exit 1
fi

# Backup (idempotent - won't overwrite an existing backup)
echo
if [ -f "${BACKUP}" ]; then
    echo "Backup already exists at ${BACKUP} ... skipping backup"
else
    cp "${DOCKERD_JSON}" "${BACKUP}"
    echo "Backed up original to ${BACKUP}"
fi

# Check python3 is available
if ! command -v python3 &>/dev/null; then
    echo
    echo "python3 not found. Cannot safely modify JSON. Stopping."
    exit 1
fi

# Apply the fix
echo
python3 - "${DOCKERD_JSON}" << 'EOF'
import sys, json

path = sys.argv[1]

with open(path, 'r') as f:
    try:
        config = json.load(f)
    except json.JSONDecodeError as e:
        print(f"ERROR: Could not parse {path}: {e}")
        sys.exit(1)

if config.get('apparmor') is False:
    print("'apparmor' is already set to false in dockerd.json. Nothing to do.")
    sys.exit(0)

config['apparmor'] = False

with open(path, 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')

print("'apparmor: false' added to dockerd.json successfully.")
EOF

# Capture python3 exit code
PYTHON_EXIT=$?
if [ "${PYTHON_EXIT}" -ne 0 ]; then
    echo
    echo "Something went wrong. Your original file is still backed up at ${BACKUP}."
    echo "Run 'sudo $0 --restore' to revert."
    exit 1
fi

echo
echo "Done. Restart Container Manager for the change to take effect:"
echo
echo "  sudo synopkg restart ContainerManager"
