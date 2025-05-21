#!/usr/bin/env bash

# Pi-hole: A black hole for Internet advertisements
# (c) 2019 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# ARP table interaction
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

coltable="/opt/pihole/COL_TABLE"
if [[ -f ${coltable} ]]; then
# shellcheck source="./advanced/Scripts/COL_TABLE"
    source ${coltable}
fi

readonly PI_HOLE_SCRIPT_DIR="/opt/pihole"
utilsfile="${PI_HOLE_SCRIPT_DIR}/utils.sh"
# shellcheck source=./advanced/Scripts/utils.sh
source "${utilsfile}"

# Determine database location
DBFILE=$(getFTLConfigValue "files.database")
if [ -z "$DBFILE" ]; then
    DBFILE="/etc/pihole/pihole-FTL.db"
fi

flushARP(){
    local output
    if [[ "${args[1]}" != "quiet" ]]; then
        echo -ne "  ${INFO} Flushing network table ..."
    fi

    # Stop FTL to prevent database access
    if ! output=$(service pihole-FTL stop 2>&1); then
        echo -e "${OVER}  ${CROSS} Failed to stop FTL"
        echo "  Output: ${output}"
        return 1
    fi

    # Truncate network_addresses table in pihole-FTL.db
    # This needs to be done before we can truncate the network table due to
    # foreign key constraints
    if ! output=$(pihole-FTL sqlite3 -ni "${DBFILE}" "DELETE FROM network_addresses" 2>&1); then
        echo -e "${OVER}  ${CROSS} Failed to truncate network_addresses table"
        echo "  Database location: ${DBFILE}"
        echo "  Output: ${output}"
        return 1
    fi

    # Truncate network table in pihole-FTL.db
    if ! output=$(pihole-FTL sqlite3 -ni "${DBFILE}" "DELETE FROM network" 2>&1); then
        echo -e "${OVER}  ${CROSS} Failed to truncate network table"
        echo "  Database location: ${DBFILE}"
        echo "  Output: ${output}"
        return 1
    fi

    # Flush ARP cache of the host
    if ! output=$(ip -s -s neigh flush all 2>&1); then
        echo -e "${OVER}  ${CROSS} Failed to flush ARP cache"
        echo "  Output: ${output}"
        return 1
    fi

    # Start FTL again
    if ! output=$(service pihole-FTL restart 2>&1); then
        echo -e "${OVER}  ${CROSS} Failed to restart FTL"
        echo "  Output: ${output}"
        return 1
    fi

    if [[ "${args[1]}" != "quiet" ]]; then
        echo -e "${OVER}  ${TICK} Flushed network table"
    fi
}

args=("$@")

case "${args[0]}" in
    "arpflush"            ) flushARP;;
esac
