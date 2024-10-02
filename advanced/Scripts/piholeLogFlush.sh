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
source ${colfile}

readonly PI_HOLE_SCRIPT_DIR="/opt/pihole"
utilsfile="${PI_HOLE_SCRIPT_DIR}/utils.sh"
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

if [[ "$*" == *"once"* ]]; then
    # Nightly logrotation
    if command -v /usr/sbin/logrotate >/dev/null; then
        # Logrotate once

        if [[ "$*" != *"quiet"* ]]; then
            echo -ne "  ${INFO} Running logrotate ..."
        fi
        /usr/sbin/logrotate --force --state "${STATEFILE}" /etc/pihole/logrotate
    else
        # Copy pihole.log over to pihole.log.1
        # and empty out pihole.log
        # Note that moving the file is not an option, as
        # dnsmasq would happily continue writing into the
        # moved file (it will have the same file handler)
        if [[ "$*" != *"quiet"* ]]; then
            echo -ne "  ${INFO} Rotating ${LOGFILE} ..."
        fi
        cp -p "${LOGFILE}" "${LOGFILE}.1"
        echo " " > "${LOGFILE}"
        chmod 640 "${LOGFILE}"
        if [[ "$*" != *"quiet"* ]]; then
            echo -e "${OVER}  ${TICK} Rotated ${LOGFILE} ..."
        fi
        # Copy FTL.log over to FTL.log.1
        # and empty out FTL.log
        if [[ "$*" != *"quiet"* ]]; then
            echo -ne "  ${INFO} Rotating ${FTLFILE} ..."
        fi
        cp -p "${FTLFILE}" "${FTLFILE}.1"
        echo " " > "${FTLFILE}"
        chmod 640 "${FTLFILE}"
        if [[ "$*" != *"quiet"* ]]; then
            echo -e "${OVER}  ${TICK} Rotated ${FTLFILE} ..."
        fi
    fi
else
    # Manual flushing

    # Flush both pihole.log and pihole.log.1 (if existing)
    if [[ "$*" != *"quiet"* ]]; then
        echo -ne "  ${INFO} Flushing ${LOGFILE} ..."
    fi
    echo " " > "${LOGFILE}"
    chmod 640 "${LOGFILE}"
    if [ -f "${LOGFILE}.1" ]; then
        echo " " > "${LOGFILE}.1"
        chmod 640 "${LOGFILE}.1"
    fi
    if [[ "$*" != *"quiet"* ]]; then
        echo -e "${OVER}  ${TICK} Flushed ${LOGFILE} ..."
    fi

    # Flush both FTL.log and FTL.log.1 (if existing)
    if [[ "$*" != *"quiet"* ]]; then
        echo -ne "  ${INFO} Flushing ${FTLFILE} ..."
    fi
    echo " " > "${FTLFILE}"
    chmod 640 "${FTLFILE}"
    if [ -f "${FTLFILE}.1" ]; then
        echo " " > "${FTLFILE}.1"
        chmod 640 "${FTLFILE}.1"
    fi
    if [[ "$*" != *"quiet"* ]]; then
        echo -e "${OVER}  ${TICK} Flushed ${FTLFILE} ..."
    fi

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

