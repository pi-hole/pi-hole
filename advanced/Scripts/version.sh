#!/usr/bin/env sh
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Show version numbers
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# Source the versions file populated by updatechecker.sh
cachedVersions="/etc/pihole/versions"

if [ -f ${cachedVersions} ]; then
    # shellcheck source=/dev/null
    . "$cachedVersions"
else
    echo "Could not find /etc/pihole/versions. Running update now."
    pihole updatechecker
     # shellcheck source=/dev/null
    . "$cachedVersions"
fi

main() {
    local details
    details=false

    # Automatically show detailed information if
    # at least one of the components is not on master branch
    if [ ! "${CORE_BRANCH}" = "master" ] || [ ! "${WEB_BRANCH}" = "master" ] || [ ! "${FTL_BRANCH}" = "master" ]; then
        details=true
    fi

    if [ "${details}" = true ]; then
        echo "Core"
        echo "    Version is ${CORE_VERSION:=N/A} (Latest: ${GITHUB_CORE_VERSION:=N/A})"
        echo "    Branch is ${CORE_BRANCH:=N/A}"
        echo "    Hash is ${CORE_HASH:=N/A} (Latest: ${GITHUB_CORE_HASH:=N/A})"
        echo "Web"
        echo "    Version is ${WEB_VERSION:=N/A} (Latest: ${GITHUB_WEB_VERSION:=N/A})"
        echo "    Branch is ${WEB_BRANCH:=N/A}"
        echo "    Hash is ${WEB_HASH:=N/A} (Latest: ${GITHUB_WEB_HASH:=N/A})"
        echo "FTL"
        echo "    Version is ${FTL_VERSION:=N/A} (Latest: ${GITHUB_FTL_VERSION:=N/A})"
        echo "    Branch is ${FTL_BRANCH:=N/A}"
        echo "    Hash is ${FTL_HASH:=N/A} (Latest: ${GITHUB_FTL_HASH:=N/A})"
    else
        echo "Core version is ${CORE_VERSION:=N/A} (Latest: ${GITHUB_CORE_VERSION:=N/A})"
        echo "Web version is ${WEB_VERSION:=N/A} (Latest: ${GITHUB_WEB_VERSION:=N/A})"
        echo "FTL version is ${FTL_VERSION:=N/A} (Latest: ${GITHUB_FTL_VERSION:=N/A})"
    fi
}

main
