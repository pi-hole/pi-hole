#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Flushes Pi-hole's log file
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

PI_HOLE_SCRIPT_DIR="${PI_HOLE_SCRIPT_DIR:-/opt/pihole}"

colfile="${PI_HOLE_SCRIPT_DIR}/COL_TABLE"
if [[ -f "${colfile}" ]]; then
    # shellcheck source="./advanced/Scripts/COL_TABLE"
    source "${colfile}"
fi

utilsfile="${PI_HOLE_SCRIPT_DIR}/utils.sh"
if [[ -f "${utilsfile}" ]]; then
    # shellcheck source="./advanced/Scripts/utils.sh"
    source "${utilsfile}"
fi

# Determine database location
if command -v getFTLConfigValue >/dev/null 2>&1; then
    DBFILE=$(getFTLConfigValue "files.database")
    LOGFILE=$(getFTLConfigValue "files.log.dnsmasq")
    FTLFILE=$(getFTLConfigValue "files.log.ftl")
    WEBFILE=$(getFTLConfigValue "files.log.webserver")
fi

if [ -z "$DBFILE" ]; then
    DBFILE="/etc/pihole/pihole-FTL.db"
fi

if [ -z "$LOGFILE" ]; then
    LOGFILE="/var/log/pihole/pihole.log"
fi

if [ -z "$FTLFILE" ]; then
    FTLFILE="/var/log/pihole/FTL.log"
fi

if [ -z "$WEBFILE" ]; then
    WEBFILE="/var/log/pihole/webserver.log"
fi

quiet=false
if [[ "$*" == *"quiet"* || "$*" == *"-q"* ]]; then
    quiet=true
fi

# Helper function to handle log flushing for a single file
flush_log() {
    local logfile="$1"
    if [[ ! -f "${logfile}" ]]; then
        return 0
    fi
    if [[ "${quiet}" != true ]]; then
        echo -ne "  ${INFO} Flushing ${logfile} ..."
    fi
    echo " " > "${logfile}"
    chmod 640 "${logfile}"
    if [ -f "${logfile}.1" ]; then
        echo " " > "${logfile}.1"
        chmod 640 "${logfile}.1"
    fi
    if [[ "${quiet}" != true ]]; then
        echo -e "${OVER}  ${TICK} Flushed ${logfile} ..."
    fi
}

if [[ "$*" == *"once"* ]]; then
    # Nightly logrotation
    # Logrotate once
    if [[ "${quiet}" != true ]]; then
        echo -ne "  ${INFO} Running logrotate ..."
    fi
    # Use logrotate's default state file so this run and the system's own
    # scheduled logrotate (which also reads /etc/logrotate.d/pihole) agree on
    # what's already been rotated, instead of rotating our logs twice.
    logrotate_cmd="/usr/sbin/logrotate"
    if [[ ! -x "${logrotate_cmd}" ]] && command -v logrotate > /dev/null 2>&1; then
        logrotate_cmd="$(command -v logrotate)"
    fi

    if "${logrotate_cmd}" --force /etc/logrotate.d/pihole; then
        if [[ "${quiet}" != true ]]; then
            echo -e "${OVER}  ${TICK} Rotated logs"
        fi
    else
        echo -e "${OVER}  ${CROSS} Failed to rotate logs" >&2
        exit 1
    fi
else
    # Manual flushing
    flush_log "${LOGFILE}"
    flush_log "${FTLFILE}"
    flush_log "${WEBFILE}"

    if [[ "${quiet}" != true ]]; then
        echo -ne "  ${INFO} Flushing database, DNS resolution temporarily unavailable ..."
    fi

    # Stop FTL to make sure it doesn't write to the database while we're deleting data
    if command -v service >/dev/null 2>&1; then
        service pihole-FTL stop
    fi

    # Delete most recent 24 hours from FTL's database, leave even older data intact (don't wipe out all history)
    if command -v pihole-FTL >/dev/null 2>&1; then
        deleted=$(pihole-FTL sqlite3 -ni "${DBFILE}" "DELETE FROM query_storage WHERE timestamp >= strftime('%s','now')-86400; select changes() from query_storage limit 1")
    else
        deleted=0
    fi

    # Restart FTL
    if command -v service >/dev/null 2>&1; then
        service pihole-FTL restart
    fi

    if [[ "${quiet}" != true ]]; then
        echo -e "${OVER}  ${TICK} Deleted ${deleted} queries from long-term query database"
    fi
fi
