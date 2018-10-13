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
    git describe --long --dirty --tags || return 1
}

# Source the setupvars config file
# shellcheck disable=SC1091
. /etc/pihole/setupVars.conf

if [[ "$2" == "remote" ]]; then

    if [[ "$3" == "reboot" ]]; then
        sleep 30
    fi

    GITHUB_VERSION_FILE="/etc/pihole/GitHubVersions"

    GITHUB_CORE_VERSION="$(json_extract tag_name "$(curl -s 'https://api.github.com/repos/pi-hole/pi-hole/releases/latest' 2> /dev/null)")"
    echo -n "${GITHUB_CORE_VERSION}" > "${GITHUB_VERSION_FILE}"

    if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then
        GITHUB_WEB_VERSION="$(json_extract tag_name "$(curl -s 'https://api.github.com/repos/pi-hole/AdminLTE/releases/latest' 2> /dev/null)")"
        echo -n " ${GITHUB_WEB_VERSION}" >> "${GITHUB_VERSION_FILE}"
    fi

    GITHUB_FTL_VERSION="$(json_extract tag_name "$(curl -s 'https://api.github.com/repos/pi-hole/FTL/releases/latest' 2> /dev/null)")"
    echo -n " ${GITHUB_FTL_VERSION}" >> "${GITHUB_VERSION_FILE}"

else

    LOCAL_BRANCH_FILE="/etc/pihole/localbranches"

    CORE_BRANCH="$(get_local_branch /etc/.pihole)"
    echo -n "${CORE_BRANCH}" > "${LOCAL_BRANCH_FILE}"

    if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then
        WEB_BRANCH="$(get_local_branch /var/www/html/admin)"
        echo -n " ${WEB_BRANCH}" >> "${LOCAL_BRANCH_FILE}"
    fi

    FTL_BRANCH="$(pihole-FTL branch)"
    echo -n " ${FTL_BRANCH}" >> "${LOCAL_BRANCH_FILE}"

    LOCAL_VERSION_FILE="/etc/pihole/localversions"

    CORE_VERSION="$(get_local_version /etc/.pihole)"
    echo -n "${CORE_VERSION}" > "${LOCAL_VERSION_FILE}"

    if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then
        WEB_VERSION="$(get_local_version /var/www/html/admin)"
        echo -n " ${WEB_VERSION}" >> "${LOCAL_VERSION_FILE}"
    fi

    FTL_VERSION="$(pihole-FTL version)"
    echo -n " ${FTL_VERSION}" >> "${LOCAL_VERSION_FILE}"

fi
