#!/usr/bin/env bash
# shellcheck disable=SC1090

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
    source ${coltable}
fi

# Determine database location
# Obtain DBFILE=... setting from pihole-FTL.db
# Constructed to return nothing when
# a) the setting is not present in the config file, or
# b) the setting is commented out (e.g. "#DBFILE=...")
FTLconf="/etc/pihole/pihole-FTL.conf"
if [ -e "$FTLconf" ]; then
    DBFILE="$(sed -n -e 's/^\s*DBFILE\s*=\s*//p' ${FTLconf})"
fi
# Test for empty string. Use standard path in this case.
if [ -z "$DBFILE" ]; then
    DBFILE="/etc/pihole/pihole-FTL.db"
fi


flushARP(){
    local output
    if [[ "$@" != *"quiet"* ]]; then
        echo -ne "  ${INFO} Flushing network table ..."
    fi

    # Flush ARP cache to avoid re-adding of dead entries
    if ! output=$(ip neigh flush all 2>&1); then
        echo -e "${OVER}  ${CROSS} Failed to clear ARP cache"
        echo "  Output: ${output}"
        return 1
    fi

    if ! output=$(sqlite3 "${DBFILE}" "DELETE FROM network;" 2>&1); then
        echo -e "${OVER}  ${CROSS} Failed to truncate network table"
        echo "  Database location: ${DBFILE}"
        echo "  Output: ${output}"
        return 1
    fi

    if [[ "$@" != *"quiet"* ]]; then
        echo -e "${OVER}  ${TICK} Flushed network table"
    fi
}

args=("$@")

case "${args[0]}" in
    "arpflush"            ) flushARP;;
esac

shift

