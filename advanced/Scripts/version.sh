#!/usr/bin/env sh
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Show version numbers
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# Source the setupvars config file
# shellcheck disable=SC1091
. /etc/pihole/setupVars.conf

# Source the versions file poupulated by updatechecker.sh
cachedVersions="/etc/pihole/versions"

if [ -f ${cachedVersions} ]; then
    # shellcheck disable=SC1090
    . "$cachedVersions"
else
    echo "Could not find /etc/pihole/versions. Running update now."
    pihole updatechecker
    # shellcheck disable=SC1090
    . "$cachedVersions"
fi

getLocalVersion() {
    case ${1} in
        "Pi-hole"   )  echo "${CORE_VERSION:=N/A}";;
        "AdminLTE"  )  [ "${INSTALL_WEB_INTERFACE}" = true ] && echo "${WEB_VERSION:=N/A}";;
        "FTL"       )  echo "${FTL_VERSION:=N/A}";;
    esac
}

getLocalHash() {
    case ${1} in
        "Pi-hole"   )  echo "${CORE_HASH:=N/A}";;
        "AdminLTE"  )  [ "${INSTALL_WEB_INTERFACE}" = true ] && echo "${WEB_HASH:=N/A}";;
        "FTL"       )  echo "${FTL_HASH:=N/A}";;
    esac
}

getRemoteHash(){
    case ${1} in
        "Pi-hole"   )  echo "${GITHUB_CORE_HASH:=N/A}";;
        "AdminLTE"  )  [ "${INSTALL_WEB_INTERFACE}" = true ] && echo "${GITHUB_WEB_HASH:=N/A}";;
        "FTL"       )  echo "${GITHUB_FTL_HASH:=N/A}";;
    esac
}

getRemoteVersion(){
    case ${1} in
        "Pi-hole"   )  echo "${GITHUB_CORE_VERSION:=N/A}";;
        "AdminLTE"  )  [ "${INSTALL_WEB_INTERFACE}" = true ] && echo "${GITHUB_WEB_VERSION:=N/A}";;
        "FTL"       )  echo "${GITHUB_FTL_VERSION:=N/A}";;
    esac
}

getLocalBranch(){
    case ${1} in
        "Pi-hole"   )  echo "${CORE_BRANCH:=N/A}";;
        "AdminLTE"  )  [ "${INSTALL_WEB_INTERFACE}" = true ] && echo "${WEB_BRANCH:=N/A}";;
        "FTL"       )  echo "${FTL_BRANCH:=N/A}";;
    esac
}

versionOutput() {
    if [ "$1" = "AdminLTE" ] && [ "${INSTALL_WEB_INTERFACE}" != true ]; then
        echo "  WebAdmin not installed"
        return 1
    fi

    [ "$2" = "-c" ] || [ "$2" = "--current" ] || [ -z "$2" ] && current=$(getLocalVersion "${1}") && branch=$(getLocalBranch "${1}")
    [ "$2" = "-l" ] || [ "$2" = "--latest" ] || [ -z "$2" ] && latest=$(getRemoteVersion "${1}")
    if [ "$2" = "--hash" ]; then
        [ "$3" = "-c" ] || [ "$3" = "--current" ] || [ -z "$3" ] && curHash=$(getLocalHash "${1}") && branch=$(getLocalBranch "${1}")
        [ "$3" = "-l" ] || [ "$3" = "--latest" ] || [ -z "$3" ] && latHash=$(getRemoteHash "${1}") && branch=$(getLocalBranch "${1}")
    fi

    # We do not want to show the branch name when we are on master,
    # blank out the variable in this case
    if [ "$branch" = "master" ]; then
        branch=""
    else
        branch="$branch "
    fi

    if [ -n "$current" ] && [ -n "$latest" ]; then
        output="${1} version is $branch$current (Latest: $latest)"
    elif [ -n "$current" ] && [ -z "$latest" ]; then
        output="Current ${1} version is $branch$current"
    elif [ -z "$current" ] && [ -n "$latest" ]; then
        output="Latest ${1} version is $latest"
    elif [ -n "$curHash" ] && [ -n "$latHash" ]; then
        output="Local ${1} hash is $curHash (Remote: $latHash)"
    elif [ -n "$curHash" ] && [ -z "$latHash" ]; then
        output="Current local ${1} hash is $curHash"
    elif [ -z "$curHash" ] && [ -n "$latHash" ]; then
        output="Latest remote ${1} hash is $latHash"
    elif [ -z "$curHash" ] && [ -z "$latHash" ]; then
        output="Hashes for ${1} not available"
    else
        errorOutput
        return 1
    fi

    [ -n "$output" ] && echo "  $output"
}

errorOutput() {
    echo "  Invalid Option! Try 'pihole -v --help' for more information."
    exit 1
}

defaultOutput() {
    versionOutput "Pi-hole" "$@"

    if [ "${INSTALL_WEB_INTERFACE}" = true ]; then
        versionOutput "AdminLTE" "$@"
    fi

    versionOutput "FTL" "$@"
}

helpFunc() {
    echo "Usage: pihole -v [repo | option] [option]
Example: 'pihole -v -p -l'
Show Pi-hole, Admin Console & FTL versions

Repositories:
  -p, --pihole         Only retrieve info regarding Pi-hole repository
  -a, --admin          Only retrieve info regarding AdminLTE repository
  -f, --ftl            Only retrieve info regarding FTL repository

Options:
  -c, --current        Return the current version
  -l, --latest         Return the latest version
  --hash               Return the GitHub hash from your local repositories
  -h, --help           Show this help dialog"
  exit 0
}

case "${1}" in
    "-p" | "--pihole"    ) shift; versionOutput "Pi-hole" "$@";;
    "-a" | "--admin"     ) shift; versionOutput "AdminLTE" "$@";;
    "-f" | "--ftl"       ) shift; versionOutput "FTL" "$@";;
    "-h" | "--help"      ) helpFunc;;
    *                    ) defaultOutput "$@";;
esac
