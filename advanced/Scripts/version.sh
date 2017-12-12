#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Show version numbers
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# Get local and remote versions using the update checker
echo "Getting local versions..."
pihole updatechecker local
echo "Getting remote versions..."
pihole updatechecker remote

COREGITDIR="/etc/.pihole/"
WEBGITDIR="/var/www/html/admin/"

read -a GitHubVersions < "/etc/pihole/GitHubVersions"
read -a GitHubPreRelease < "/etc/pihole/GitHubPreRelease"
read -a localbranches < "/etc/pihole/localbranches"
read -a localversions < "/etc/pihole/localversions"

getLocalHash() {
  # Local FTL hash does not exist on filesystem
  if [[ "$1" == "FTL" ]]; then
    echo "N/A"
    return 0
  fi

  # Get the short hash of the local repository
  local directory="${1}"
  local hash

  cd "${directory}" 2> /dev/null || { echo "${DEFAULT}"; return 1; }
  hash=$(git rev-parse --short HEAD || echo "$DEFAULT")
  if [[ "${hash}" == "${DEFAULT}" ]]; then
    echo "ERROR"
    return 1
  else
    echo "${hash}"
  fi
  return 0
}

getRemoteHash(){
  # Remote FTL hash is not applicable
  if [[ "$1" == "FTL" ]]; then
    echo "N/A"
    return 0
  fi

  local daemon="${1}"
  local branch="${2}"

  hash=$(git ls-remote --heads "https://github.com/pi-hole/${daemon}" | \
         awk -v bra="$branch" '$0~bra {print substr($0,0,8);exit}')
  if [[ -n "$hash" ]]; then
    echo "$hash"
  else
    echo "ERROR"
    return 1
  fi
  return 0
}

versionOutput() {

  if [[ "$1" == "0" ]]; then
    NAME="Pi-hole core"
    GITDIR="${COREGITDIR}"
  elif [[ "$1" == "1" ]]; then
    NAME="Pi-hole web"
    GITDIR="${WEBGITDIR}"
  elif [[ "$1" == "2" ]]; then
    NAME="Pi-hole FTL"
    GITDIR="FTL"
  fi

  if [[ "$2" == "-c" || "$2" == "--current" || -z "$2" ]]; then
    current=${localversions[$1]}
  fi

  if [[ "$2" == "-l" || "$2" == "--latest" || -z "$2" ]]; then
    latest=${GitHubVersions[$1]}
  fi

  if [[ "$2" == "--hash" ]]; then
    if [[ "$3" == "-c" || "$3" == "--current" || -z "$3" ]]; then
      curHash=$(getLocalHash "$GITDIR")
    fi
    if [[ "$3" == "-l" || "$3" == "--latest" || -z "$3" ]]; then
      latHash=$(getRemoteHash "$1" "$(cd "$GITDIR" 2> /dev/null && git rev-parse --abbrev-ref HEAD)")
    fi
  fi

  curbeta=${GitHubPreRelease[$1]}

  if [[ "$2" == "--branch" ]]; then
    curbranch=${localbranches[$1]}
  fi

  if [[ -n "$current" ]] && [[ -n "$latest" ]]; then
    output="${NAME} version is $current (Latest: $latest)"
  elif [[ -n "$current" ]] && [[ -z "$latest" ]]; then
    output="Current ${NAME} version is $current"
  elif [[ -z "$current" ]] && [[ -n "$latest" ]]; then
    output="Latest ${NAME} version is $latest"
  elif [[ "$curHash" == "N/A" ]] || [[ "$latHash" == "N/A" ]]; then
    output="${NAME} hash is not applicable"
  elif [[ -n "$curHash" ]] && [[ -n "$latHash" ]]; then
    output="${NAME} hash is $curHash (Latest: $latHash)"
  elif [[ -n "$curHash" ]] && [[ -z "$latHash" ]]; then
    output="Current ${NAME} hash is $curHash"
  elif [[ -z "$curHash" ]] && [[ -n "$latHash" ]]; then
    output="Latest ${NAME} hash is $latHash"
  elif [[ -n "$curbranch" ]]; then
    output="Local ${NAME} branch is $curbranch"
  elif [[ -n "$curbeta" ]]; then
    if [[ "$curbeta" == "true" ]]; then
      output="Current ${NAME} release is a beta release"
    else
      output="Current ${NAME} release is a regular release"
    fi
  else
    errorOutput
  fi

  if [[ "$curbeta" == "true" ]]; then
    output="${output} (this is a beta release)"
  fi

  [[ -n "$output" ]] && echo "  $output"
}

errorOutput() {
  echo "  Invalid Option! Try 'pihole -v --help' for more information."
  exit 1
}

defaultOutput() {
  versionOutput "0" "$@"
  versionOutput "1" "$@"
  versionOutput "2" "$@"
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
  --hash               Return the Github hash from your local repositories
  --beta               Return if latest versions on GitHub are beta releases
  --branch             Return the local branches
  -h, --help           Show this help dialog"
  exit 0
}

case "${1}" in
  "-p" | "--pihole"    ) shift; versionOutput "0" "$@";;
  "-a" | "--admin"     ) shift; versionOutput "1" "$@";;
  "-f" | "--ftl"       ) shift; versionOutput "2" "$@";;
  "-h" | "--help"      ) helpFunc;;
  *                    ) defaultOutput "$@";;
esac
