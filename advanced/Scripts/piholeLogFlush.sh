#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Flushes Pi-hole's log file
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

colfile="/opt/pihole/COL_TABLE"
# shellcheck source="./advanced/Scripts/COL_TABLE"
source ${colfile}

readonly PI_HOLE_SCRIPT_DIR="/opt/pihole"
utilsfile="${PI_HOLE_SCRIPT_DIR}/utils.sh"
# shellcheck source="./advanced/Scripts/utils.sh"
source "${utilsfile}"

# In case we're running at the same time as a system logrotate, use a
# separate logrotate state file to prevent stepping on each other's
# toes.
STATEFILE="/var/lib/logrotate/pihole"

# Determine database location
DBFILE=$(getFTLConfigValue "files.database")
if [ -z "$DBFILE" ]; then
    DBFILE="/etc/pihole/pihole-FTL.db"
fi

# Determine log file location
LOGFILE=$(getFTLConfigValue "files.log.dnsmasq")
if [ -z "$LOGFILE" ]; then
    LOGFILE="/var/log/pihole/pihole.log"
fi
FTLFILE=$(getFTLConfigValue "files.log.ftl")
if [ -z "$FTLFILE" ]; then
    FTLFILE="/var/log/pihole/FTL.log"
fi
WEBFILE=$(getFTLConfigValue "files.log.webserver")
if [ -z "$WEBFILE" ]; then
    WEBFILE="/var/log/pihole/webserver.log"
fi

# Helper function to handle log flushing for a single file
flush_log() {
    local logfile="$1"
    if [[ "$*" != *"quiet"* ]]; then
        echo -ne "  ${INFO} Flushing ${logfile} ..."
    fi
    echo " " > "${logfile}"
    chmod 640 "${logfile}"
    if [ -f "${logfile}.1" ]; then
        echo " " > "${logfile}.1"
        chmod 640 "${logfile}.1"
    fi
    if [[ "$*" != *"quiet"* ]]; then
        echo -e "${OVER}  ${TICK} Flushed ${logfile} ..."
    fi
}

if [[ "$*" == *"once"* ]]; then
    # Nightly logrotation
    # Logrotate once
    if [[ "$*" != *"quiet"* ]]; then
        echo -ne "  ${INFO} Running logrotate ..."
    fi
    mkdir -p "${STATEFILE%/*}"
    /usr/sbin/logrotate --force --state "${STATEFILE}" /etc/logrotate.d/pihole
else
    # Validate DBFILE path before making any changes
    if [[ ! "${DBFILE}" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
        echo -e "  ${COL_RED}[✗] Invalid database file path: ${DBFILE}${COL_NC}"
        exit 1
    fi

    # Manual flushing
    flush_log "${LOGFILE}"
    flush_log "${FTLFILE}"
    flush_log "${WEBFILE}"

    if [[ "$*" != *"quiet"* ]]; then
        echo -ne "  ${INFO} Flushing database, DNS resolution temporarily unavailable ..."
    fi

    # Stop FTL to make sure it doesn't write to the database while we're deleting data
    service pihole-FTL stop

    # Delete most recent 24 hours from FTL's database, leave even older data intact (don't wipe out all history)
    deleted=$(pihole-FTL sqlite3 -ni -- "${DBFILE}" "DELETE FROM query_storage WHERE timestamp >= strftime('%s','now')-86400; select changes() from query_storage limit 1")

    # Restart FTL
    service pihole-FTL restart
    if [[ "$*" != *"quiet"* ]]; then
        echo -e "${OVER}  ${TICK} Deleted ${deleted} queries from long-term query database"
    fi
fi
