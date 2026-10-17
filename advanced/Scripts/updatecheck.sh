#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Checks for local or remote versions and branches
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

set -o pipefail

# This script writes into /etc/pihole, which is owned by the unprivileged
# "pihole" user. Anything root does there by name can be redirected by a
# symlink that user plants (GHSA-xch2-4qxw-g5vj), so never do that work as root:
# when started as root (the installer, `pihole -up`, `pihole checkout`,
# `sudo pihole updatechecker`, ...) hand over to the pihole user and exit with
# its result. The pihole user can only ever damage what it already owns.
if [[ "$(id -u)" -eq 0 ]]; then
    # Only the literal "reboot" argument (see below) is passed on
    reboot_arg=""
    [[ "${1:-}" == "reboot" ]] && reboot_arg="reboot"
    su -s /bin/sh pihole -c "/opt/pihole/updatecheck.sh ${reboot_arg}"
    exit "$?"
fi

function get_local_branch() {
    # Return active branch
    cd "${1}" 2>/dev/null || { echo "null"; return; }
    git rev-parse --abbrev-ref HEAD || echo "null"
}

function get_local_version() {
    # Return active version
    cd "${1}" 2>/dev/null || { echo "null"; return; }
    git describe --tags --always 2>/dev/null || echo "null"
}

function get_local_hash() {
    cd "${1}" 2>/dev/null || { echo "null"; return; }
    git rev-parse --short=8 HEAD || echo "null"
}

function get_remote_version() {
    # if ${2} is = "master" we need to use the "latest" endpoint, otherwise, we simply return null
    if [[ "${2}" == "master" ]]; then
        curl -s "https://api.github.com/repos/pi-hole/${1}/releases/latest" 2>/dev/null | jq --raw-output .tag_name || echo "null"
    else
        echo "null"
    fi
}

function get_remote_hash() {
    git ls-remote "https://github.com/pi-hole/${1}" --tags "${2}" | awk '{print substr($0, 1,8);}' || echo "null"
}

# Source the utils file for addOrEditKeyValPair()
# shellcheck source="./advanced/Scripts/utils.sh"
. /opt/pihole/utils.sh

ADMIN_INTERFACE_DIR=$(getFTLConfigValue "webserver.paths.webroot")$(getFTLConfigValue "webserver.paths.webhome")
readonly ADMIN_INTERFACE_DIR

# Remove the below three legacy files if they exist
rm -f "/etc/pihole/GitHubVersions"
rm -f "/etc/pihole/localbranches"
rm -f "/etc/pihole/localversions"

VERSION_FILE="/etc/pihole/versions"

# Assemble the versions file in a temporary file next to it and move it into
# place at the very end of this script, so readers never see a half-written
# file. (Running as the pihole user, see above, the temporary file lives in a
# directory only that user can modify.)
VERSION_FILE_TMP="$(mktemp "${VERSION_FILE}.XXXXXX")" || exit 1
trap 'rm -f "${VERSION_FILE_TMP}"' EXIT

# if /pihole.docker.tag file exists, we will use it's value later in this script
DOCKER_TAG=$(cat /pihole.docker.tag 2>/dev/null)
release_regex='^([0-9]+\.){1,2}(\*|[0-9]+)(-.*)?$'
regex=$release_regex'|(^nightly$)|(^dev.*$)'
if [[ ! "${DOCKER_TAG}" =~ $regex ]]; then
    # DOCKER_TAG does not match the pattern (see https://regex101.com/r/RsENuz/1), so unset it.
    unset DOCKER_TAG
fi

# used in cronjob
if [[ "$1" == "reboot" ]]; then
    sleep 30
fi

# get Core versions

CORE_VERSION="$(get_local_version /etc/.pihole)"
addOrEditKeyValPair "${VERSION_FILE_TMP}" "CORE_VERSION" "${CORE_VERSION}"

CORE_BRANCH="$(get_local_branch /etc/.pihole)"
addOrEditKeyValPair "${VERSION_FILE_TMP}" "CORE_BRANCH" "${CORE_BRANCH}"

CORE_HASH="$(get_local_hash /etc/.pihole)"
addOrEditKeyValPair "${VERSION_FILE_TMP}" "CORE_HASH" "${CORE_HASH}"

GITHUB_CORE_VERSION="$(get_remote_version pi-hole "${CORE_BRANCH}")"
addOrEditKeyValPair "${VERSION_FILE_TMP}" "GITHUB_CORE_VERSION" "${GITHUB_CORE_VERSION}"

GITHUB_CORE_HASH="$(get_remote_hash pi-hole "${CORE_BRANCH}")"
addOrEditKeyValPair "${VERSION_FILE_TMP}" "GITHUB_CORE_HASH" "${GITHUB_CORE_HASH}"

# get Web versions

WEB_VERSION="$(get_local_version "${ADMIN_INTERFACE_DIR}")"
addOrEditKeyValPair "${VERSION_FILE_TMP}" "WEB_VERSION" "${WEB_VERSION}"

WEB_BRANCH="$(get_local_branch "${ADMIN_INTERFACE_DIR}")"
addOrEditKeyValPair "${VERSION_FILE_TMP}" "WEB_BRANCH" "${WEB_BRANCH}"

WEB_HASH="$(get_local_hash "${ADMIN_INTERFACE_DIR}")"
addOrEditKeyValPair "${VERSION_FILE_TMP}" "WEB_HASH" "${WEB_HASH}"

GITHUB_WEB_VERSION="$(get_remote_version web "${WEB_BRANCH}")"
addOrEditKeyValPair "${VERSION_FILE_TMP}" "GITHUB_WEB_VERSION" "${GITHUB_WEB_VERSION}"

GITHUB_WEB_HASH="$(get_remote_hash web "${WEB_BRANCH}")"
addOrEditKeyValPair "${VERSION_FILE_TMP}" "GITHUB_WEB_HASH" "${GITHUB_WEB_HASH}"

# get FTL versions

FTL_VERSION="$(pihole-FTL version)"
addOrEditKeyValPair "${VERSION_FILE_TMP}" "FTL_VERSION" "${FTL_VERSION}"

FTL_BRANCH="$(pihole-FTL branch)"
addOrEditKeyValPair "${VERSION_FILE_TMP}" "FTL_BRANCH" "${FTL_BRANCH}"

FTL_HASH="$(pihole-FTL --hash)"
addOrEditKeyValPair "${VERSION_FILE_TMP}" "FTL_HASH" "${FTL_HASH}"

GITHUB_FTL_VERSION="$(get_remote_version FTL "${FTL_BRANCH}")"
addOrEditKeyValPair "${VERSION_FILE_TMP}" "GITHUB_FTL_VERSION" "${GITHUB_FTL_VERSION}"

GITHUB_FTL_HASH="$(get_remote_hash FTL "${FTL_BRANCH}")"
addOrEditKeyValPair "${VERSION_FILE_TMP}" "GITHUB_FTL_HASH" "${GITHUB_FTL_HASH}"

# get Docker versions

if [[ "${DOCKER_TAG}" ]]; then
    addOrEditKeyValPair "${VERSION_FILE_TMP}" "DOCKER_VERSION" "${DOCKER_TAG}"

    # Remote version check only if the tag is a valid release version
    docker_branch=""
    if [[ "${DOCKER_TAG}" =~ $release_regex ]]; then
        docker_branch="master"
    fi

    GITHUB_DOCKER_VERSION="$(get_remote_version docker-pi-hole "${docker_branch}")"
    addOrEditKeyValPair "${VERSION_FILE_TMP}" "GITHUB_DOCKER_VERSION" "${GITHUB_DOCKER_VERSION}"
fi

# Make the assembled file world-readable ("other" needs read access so any local
# user can run `pihole -v`).
chmod 0644 "${VERSION_FILE_TMP}"

# Publish the assembled file. mv on a single file within the same filesystem
# calls rename(2), which replaces the directory entry at "${VERSION_FILE}"
# itself, so whatever was there before (even a symlink) is swapped out. -T
# makes mv treat "${VERSION_FILE}" as the file to replace, never as a directory
# to move the temporary file into.
mv -fT "${VERSION_FILE_TMP}" "${VERSION_FILE}"
