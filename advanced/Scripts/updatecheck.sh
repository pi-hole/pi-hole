#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Checks for local or remote versions and branches
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# Credit: https://stackoverflow.com/a/46324904
function json_extract() {
    local key=$1
    local json=$2

    local string_regex='"([^"\]|\\.)*"'
    local number_regex='-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?'
    local value_regex="${string_regex}|${number_regex}|true|false|null"
    local pair_regex="\"${key}\"[[:space:]]*:[[:space:]]*(${value_regex})"

    if [[ ${json} =~ ${pair_regex} ]]; then
        echo $(sed 's/^"\|"$//g' <<< "${BASH_REMATCH[1]}")
    else
        return 1
    fi
}

function get_local_branch() {
    # Return active branch
    cd "${1}" 2> /dev/null || return 1
    git rev-parse --abbrev-ref HEAD || return 1
}

function get_local_version() {
    # Return active branch
    cd "${1}" 2> /dev/null || return 1
    git describe --long --dirty --tags 2> /dev/null || return 1
}

# Source the setupvars config file
# shellcheck disable=SC1091
. /etc/pihole/setupVars.conf

utilsfile="/opt/pihole/utils.sh"
source "${utilsfile}"

# Remove the below three legacy files if they exist
GITHUB_VERSION_FILE="/etc/pihole/GitHubVersions"
LOCAL_BRANCH_FILE="/etc/pihole/localbranches"
LOCAL_VERSION_FILE="/etc/pihole/localversions"

if [ -f "${GITHUB_VERSION_FILE}" ]; then
    rm "${GITHUB_VERSION_FILE}"
fi

if [ -f "${LOCAL_BRANCH_FILE}" ]; then
    rm "${LOCAL_BRANCH_FILE}"
fi

if [ -f "${LOCAL_VERSION_FILE}" ]; then
    rm "${LOCAL_VERSION_FILE}"
fi

# Create new versions file if it does not exist
VERSION_FILE="/etc/pihole/versions"

if [ ! -f "${VERSION_FILE}" ]; then
    touch "${VERSION_FILE}"
    chmod 644 "${VERSION_FILE}"
fi

if [[ "$2" == "remote" ]]; then

    if [[ "$3" == "reboot" ]]; then
        sleep 30
    fi

    GITHUB_CORE_VERSION="$(json_extract tag_name "$(curl -s 'https://api.github.com/repos/pi-hole/pi-hole/releases/latest' 2> /dev/null)")"
    addOrEditKeyValPair "${VERSION_FILE}" "GITHUB_CORE_VERSION" "${GITHUB_CORE_VERSION}"

    if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then
        GITHUB_WEB_VERSION="$(json_extract tag_name "$(curl -s 'https://api.github.com/repos/pi-hole/AdminLTE/releases/latest' 2> /dev/null)")"
        addOrEditKeyValPair "${VERSION_FILE}" "GITHUB_WEB_VERSION" "${GITHUB_WEB_VERSION}"
    fi

    GITHUB_FTL_VERSION="$(json_extract tag_name "$(curl -s 'https://api.github.com/repos/pi-hole/FTL/releases/latest' 2> /dev/null)")"
    addOrEditKeyValPair "${VERSION_FILE}" "GITHUB_FTL_VERSION" "${GITHUB_FTL_VERSION}"

    if [[ "${PIHOLE_DOCKER_TAG}" ]]; then
        GITHUB_DOCKER_VERSION="$(json_extract tag_name "$(curl -s 'https://api.github.com/repos/pi-hole/docker-pi-hole/releases/latest' 2> /dev/null)")"
        addOrEditKeyValPair "${VERSION_FILE}" "GITHUB_DOCKER_VERSION" "${GITHUB_DOCKER_VERSION}"
    fi

else

    CORE_BRANCH="$(get_local_branch /etc/.pihole)"
    addOrEditKeyValPair "${VERSION_FILE}" "CORE_BRANCH" "${CORE_BRANCH}"

    if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then
        WEB_BRANCH="$(get_local_branch /var/www/html/admin)"
        addOrEditKeyValPair "${VERSION_FILE}" "WEB_BRANCH" "${WEB_BRANCH}"
    fi

    FTL_BRANCH="$(pihole-FTL branch)"
    addOrEditKeyValPair "${VERSION_FILE}" "FTL_BRANCH" "${FTL_BRANCH}"

    CORE_VERSION="$(get_local_version /etc/.pihole)"
    addOrEditKeyValPair "${VERSION_FILE}" "CORE_VERSION" "${CORE_VERSION}"

    if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then
        WEB_VERSION="$(get_local_version /var/www/html/admin)"
        addOrEditKeyValPair "${VERSION_FILE}" "WEB_VERSION" "${WEB_VERSION}"
    fi

    FTL_VERSION="$(pihole-FTL version)"
    addOrEditKeyValPair "${VERSION_FILE}" "FTL_VERSION" "${FTL_VERSION}"

fi
