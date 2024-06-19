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
    LOGFILE="/var/log/pihole.log"
fi

if [[ "$*" != *"quiet"* ]]; then
    echo -ne "  ${INFO} Flushing "${LOGFILE}" ..."
fi
if [[ "$*" == *"once"* ]]; then
    # Nightly logrotation
    if command -v /usr/sbin/logrotate >/dev/null; then
        # Logrotate once
        /usr/sbin/logrotate --force --state "${STATEFILE}" /etc/pihole/logrotate
    else
        # Copy pihole.log over to pihole.log.1
        # and empty out pihole.log
        # Note that moving the file is not an option, as
        # dnsmasq would happily continue writing into the
        # moved file (it will have the same file handler)
        cp -p "${LOGFILE}" "${LOGFILE}.1"
        echo " " > "${LOGFILE}"
        chmod 640 "${LOGFILE}"
    fi
else
    # Manual flushing
    if command -v /usr/sbin/logrotate >/dev/null; then
        # Logrotate twice to move all data out of sight of FTL
        /usr/sbin/logrotate --force --state "${STATEFILE}" /etc/pihole/logrotate; sleep 3
        /usr/sbin/logrotate --force --state "${STATEFILE}" /etc/pihole/logrotate
    else
        # Flush both pihole.log and pihole.log.1 (if existing)
        echo " " > "${LOGFILE}"
        if [ -f "${LOGFILE}.1" ]; then
            echo " " > "${LOGFILE}.1"
            chmod 640 "${LOGFILE}.1"
        fi
    fi

    # Stop FTL to make sure it doesn't write to the database while we're deleting data
    service pihole-FTL stop

    # Delete most recent 24 hours from FTL's database, leave even older data intact (don't wipe out all history)
    deleted=$(pihole-FTL sqlite3 -ni "${DBFILE}" "DELETE FROM query_storage WHERE timestamp >= strftime('%s','now')-86400; select changes() from query_storage limit 1")

    # Restart FTL
    service pihole-FTL restart
fi

if [[ "$*" != *"quiet"* ]]; then
    echo -e "${OVER}  ${TICK} Flushed /var/log/pihole/pihole.log"
    echo -e "  ${TICK} Deleted ${deleted} queries from database"
fi
