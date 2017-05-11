#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# shows version numbers
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# Variables
DEFAULT="-1"
PHGITDIR="/etc/.pihole/"
WEBGITDIR="/var/www/html/admin/"

getLocalVersion() {
  # Get the tagged version of the local repository
  local directory="${1}"
  local version

  cd "${directory}" || { echo "${DEFAULT}"; return 1; }
  version=$(git describe --tags --always || \
            echo "${DEFAULT}")
  if [[ "${version}" =~ ^v ]]; then
    echo "${version}"
  elif [[ "${version}" == "${DEFAULT}" ]]; then
    echo "ERROR"
    return 1
  else
    echo "Untagged"
  fi
  return 0
}

getLocalHash() {
  # Get the short hash of the local repository
  local directory="${1}"
  local hash

  cd "${directory}" || { echo "${DEFAULT}"; return 1; }
  hash=$(git rev-parse --short HEAD || \
         echo "${DEFAULT}")
  if [[ "${hash}" == "${DEFAULT}" ]]; then
    echo "ERROR"
    return 1
  else
    echo "${hash}"
  fi
  return 0
}

getRemoteVersion(){
  # Get the version from the remote origin
  local daemon="${1}"
  local version

  version=$(curl --silent --fail https://api.github.com/repos/pi-hole/${daemon}/releases/latest | \
            awk -F: '$1 ~/tag_name/ { print $2 }' | \
            tr -cd '[[:alnum:]]._-')
  if [[ "${version}" =~ ^v ]]; then
    echo "${version}"
  else
    echo "ERROR"
    return 1
  fi
  return 0
}

coreOutput() {
  [ "$1" = "-c" -o "$1" = "--current" -o -z "$1" ] && current="$(getLocalVersion ${PHGITDIR})"
  [ "$1" = "-l" -o "$1" = "--latest" -o -z "$1" ] && latest="$(getRemoteVersion pi-hole)"
  [ "$1" = "-h" -o "$1" = "--hash" ] && hash="$(getLocalHash ${PHGITDIR})"
  [ -n "$2" ] && error="true"

  if [ -n "$current" -a -n "$latest" ]; then
    str="Pi-hole version is $current (Latest: $latest)"
  elif [ -n "$current" -a -z "$latest" ]; then
    str="Current Pi-hole version is $current"
  elif [ -z "$current" -a -n "$latest" ]; then
    str="Latest Pi-hole version is $latest"
  elif [ -n "$hash" ]; then
    str="Current Pi-hole hash is $hash"
  else
    error="true"
  fi

  if [ "$error" = "true" ]; then
    echo "  Invalid Option! Try 'pihole -v --help' for more information."
    exit 1
  fi

  echo "  $str"
}

webOutput() {
  [ "$1" = "-c" -o "$1" = "--current" -o -z "$1" ] && current="$(getLocalVersion ${WEBGITDIR})"
  [ "$1" = "-l" -o "$1" = "--latest" -o -z "$1" ] && latest="$(getRemoteVersion AdminLTE)"
  [ "$1" = "-h" -o "$1" = "--hash" ] && hash="$(getLocalHash ${WEBGITDIR})"
  [ ! -d "${WEBGITDIR}" ] && str="Web interface not installed!"
  [ -n "$2" ] && error="true"

  
  if [ -n "$current" -a -n "$latest" ]; then
    str="Admin Console version is $current (Latest: $latest)"
  elif [ -n "$current" -a -z "$latest" ]; then
    str="Current Admin Console version is $current"
  elif [ -z "$current" -a -n "$latest" ]; then
    str="Latest Admin Console version is $latest"
  elif [ -n "$hash" ]; then
    str="Current Admin Console hash is $hash"
  else
    error="true"
  fi

  if [ "$error" = "true" ]; then
    echo "  Invalid Option! Try 'pihole -v --help' for more information."
    exit 1
  fi

  echo "  $str"
}

ftlOutput() {
  [ "$1" = "-c" -o "$1" = "--current" -o -z "$1" ] && current="$(pihole-FTL version)"
  [ "$1" = "-l" -o "$1" = "--latest" -o -z "$1" ] && latest="$(getRemoteVersion FTL)"
  [ ! -d "${WEBGITDIR}" ] && exit 0
  [ -n "$2" ] && error="true"

  if [ -n "$current" -a -n "$latest" ]; then
    str="FTL version is $current (Latest: $latest)"
  elif [ -n "$current" -a -z "$latest" ]; then
    str="Current FTL version is $current"
  elif [ -z "$current" -a -n "$latest" ]; then
    str="Latest FTL version is $latest"
  else
    error="true"
  fi

  if [ "$error" = "true" ]; then
    echo "  Invalid Option! Try 'pihole -v --help' for more information."
    exit 1
  fi

  echo "  $str"
}
  
defaultOutput() {
  coreOutput "$1" "$2"
  webOutput "$1" "$2"
  ftlOutput "$1" "$2"
}

helpFunc() {
  echo "Usage: pihole -v [REPO | OPTION] [OPTION]
Show Pi-hole, Web Admin & FTL versions

Repositories:
  -a, --admin          Show both current and latest versions of Web Admin
  -f, --ftl            Show both current and latest versions of FTL
  -p, --pihole         Show both current and latest versions of Pi-hole Core
  
Options:
  -c, --current        (Only after -a | -p | -f) Return the current version
  -l, --latest         (Only after -a | -p | -f) Return the latest version
  -h, --hash           (Only after -a | -p) Return the current Github hash
  --help               Show this help dialog
"
	exit 0
}

case "${1}" in
  "-a" | "--admin"     ) shift; webOutput "$@";;
  "-p" | "--pihole"    ) shift; coreOutput "$@";;
  "-f" | "--ftl"       ) shift; ftlOutput "$@";;
  "--help"             ) helpFunc;;
  *                    ) defaultOutput "$@";;
esac
