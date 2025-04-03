#!/usr/bin/env sh

# Source utils.sh for getFTLConfigValue()
PI_HOLE_SCRIPT_DIR='/opt/pihole'
utilsfile="${PI_HOLE_SCRIPT_DIR}/utils.sh"
# shellcheck disable=SC1090
. "${utilsfile}"

# Get file paths
FTL_PID_FILE="$(getFTLConfigValue files.pid)"

# Cleanup
rm -f /run/pihole/FTL.sock /dev/shm/FTL-* "${FTL_PID_FILE}"
