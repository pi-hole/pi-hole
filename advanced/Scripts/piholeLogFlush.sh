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

PI_HOLE_SCRIPT_DIR="/opt/pihole"
utilsfile="${PI_HOLE_SCRIPT_DIR}/utils.sh"
# shellcheck source="./advanced/Scripts/utils.sh"
source "${utilsfile}"

# Source api functions
# shellcheck source="./advanced/Scripts/api.sh"
. "${PI_HOLE_SCRIPT_DIR}/api.sh"

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

# The log paths come from the pihole-owned config, so never write to them as root
as_pihole() {
    if [[ "${EUID}" -eq 0 ]]; then
        sudo -u pihole "$@"
    else
        "$@"
    fi
}

# Helper function to handle log flushing for a single file
flush_log() {
    local logfile="$1"
    if [[ "$*" != *"quiet"* ]]; then
        echo -ne "  ${INFO} Flushing ${logfile} ..."
    fi
    as_pihole sh -c 'echo " " > "$1" && chmod 640 "$1"' sh "${logfile}"
    if [ -f "${logfile}.1" ]; then
        as_pihole sh -c 'echo " " > "$1" && chmod 640 "$1"' sh "${logfile}.1"
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
    # Use logrotate's default state file so this run and the system's own
    # scheduled logrotate (which also reads /etc/logrotate.d/pihole) agree on
    # what's already been rotated, instead of rotating our logs twice.
    /usr/sbin/logrotate --force /etc/logrotate.d/pihole
else
    # Manual flushing
    flush_log "${LOGFILE}"
    flush_log "${FTLFILE}"
    flush_log "${WEBFILE}"

    if [[ "$*" != *"quiet"* ]]; then
        echo -ne "  ${INFO} Flushing the queries of the last 24 hours ..."
    fi

    # Authenticate with FTL
    LoginAPI

    # FTL drops the queries from memory and from its database while it keeps
    # running, so DNS stays up and no service manager is needed
    data=$(PostFTLData "action/flush/logs" "" "status")

    # Separate the status from the data
    status=$(printf %s "${data#"${data%???}"}")
    data=$(printf %s "${data%???}")

    # If there is an .error object in the returned data, display it
    error=$(jq --compact-output <<< "${data}" '.error')
    if [[ ${error} != "null" && ${error} != "" ]]; then
        echo -e "${OVER}  ${CROSS} Failed to flush the queries:"
        echo -e "      $(jq <<< "${data}" '.error')"
        LogoutAPI
        exit 1
    elif [[ "${status}" == "200" && "$*" != *"quiet"* ]]; then
        echo -e "${OVER}  ${TICK} Flushed the queries of the last 24 hours"
    fi

    # Delete session
    LogoutAPI
fi
