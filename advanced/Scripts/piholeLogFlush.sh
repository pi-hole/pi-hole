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

# Helper function to handle log rotation for a single file
rotate_log() {
    # This function copies x.log over to x.log.1
    # and then empties x.log
    # Note that moving the file is not an option, as
    # dnsmasq would happily continue writing into the
    # moved file (it will have the same file handler)
    local logfile="$1"
    if [[ "$*" != *"quiet"* ]]; then
        echo -ne "  ${INFO} Rotating ${logfile} ..."
    fi
    cp -p "${logfile}" "${logfile}.1"
    echo " " > "${logfile}"
    chmod 640 "${logfile}"
    if [[ "$*" != *"quiet"* ]]; then
        echo -e "${OVER}  ${TICK} Rotated ${logfile} ..."
    fi
}

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
    if command -v /usr/sbin/logrotate >/dev/null; then
        # Logrotate once

        if [[ "$*" != *"quiet"* ]]; then
            echo -ne "  ${INFO} Running logrotate ..."
        fi
        /usr/sbin/logrotate --force --state "${STATEFILE}" /etc/pihole/logrotate
    else
        # Handle rotation for each log file
        rotate_log "${LOGFILE}"
        rotate_log "${FTLFILE}"
        rotate_log "${WEBFILE}"
    fi
else
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
    deleted=$(pihole-FTL sqlite3 -ni "${DBFILE}" "DELETE FROM query_storage WHERE timestamp >= strftime('%s','now')-86400; select changes() from query_storage limit 1")

    # Restart FTL
    service pihole-FTL restart
    if [[ "$*" != *"quiet"* ]]; then
        echo -e "${OVER}  ${TICK} Deleted ${deleted} queries from long-term query database"
    fi
fi

