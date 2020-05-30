#!/bin/bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2019 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Wrapper script to re-enable Pi-hole after a period of it being disabled.
#
# This script will be aborted by the `pihole enable` command using `killall`.
# As a consequence, the filename of this script is limited to max 15 characters
# and the script does not use `env`.
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

readonly PI_HOLE_BIN_DIR="/usr/local/bin"

sleep "${1}"
"${PI_HOLE_BIN_DIR}"/pihole enable
