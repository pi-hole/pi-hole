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

getLocalPHVersion(){
  # Get the tagged version of the local Pi-hole repository
  local version
  local hash

  cd "${PHGITDIR}" || { PHVERSION="${DEFAULT}"; return 1; }
  version=$(git describe --tags --always || \
            echo "${DEFAULT}")
  if [[ "${version}" =~ ^v ]]; then
    PHVERSION="${version}"
  elif [[ "${version}" == "${DEFAULT}" ]]; then
    PHVERSION="ERROR"
  else
    PHVERSION="Untagged"
  fi

  hash=$(git rev-parse --short HEAD || \
         echo "${DEFAULT}")
  if [[ "${hash}" == "${DEFAULT}" ]]; then
    PHHASH="ERROR"
  else
    PHHASH="${hash}"
  fi
  return 0
}

getLocalWebVersion(){
  # Get the tagged version of the local Pi-hole repository
  local version
  local hash

  cd "${WEBGITDIR}" || { WEBVERSION="${DEFAULT}"; return 1; }
  version=$(git describe --tags --always || \
            echo "${DEFAULT}")
  if [[ "${version}" =~ ^v ]]; then
    WEBVERSION="${version}"
  elif [[ "${version}" == "${DEFAULT}" ]]; then
    WEBVERSION="ERROR"
  else
    WEBVERSION="Untagged"
  fi

  hash=$(git rev-parse --short HEAD || \
         echo "${DEFAULT}")
  if [[ "${hash}" == "${DEFAULT}" ]]; then
    WEBHASH="ERROR"
  else
    WEBHASH="${hash}"
  fi
  return 0
}

PHVERSIONLATEST=$(curl -s https://api.github.com/repos/pi-hole/pi-hole/releases/latest | \
                      awk -F: '$1 ~/tag_name/ { print $2 }' | \
                      tr -cd '[[:alnum:]]._-')
WEBVERSIONLATEST=$(curl -s https://api.github.com/repos/pi-hole/AdminLTE/releases/latest | \
                      awk -F: '$1 ~/tag_name/ { print $2 }' | \
                      tr -cd '[[:alnum:]]._-')

#PHHASHLATEST=$(curl -s https://api.github.com/repos/pi-hole/pi-hole/commits/master | \
#                   grep sha | \
#                   head -n1 | \
#                   awk -F ' ' '{ print $2 }' | \
#                   tr -cd '[[:alnum:]]._-')

#WEBHASHLATEST=$(curl -s https://api.github.com/repos/pi-hole/AdminLTE/commits/master | \
#                   grep sha | \
#                   head -n1 | \
#                   awk -F ' ' '{ print $2 }' | \
#                   tr -cd '[[:alnum:]]._-')


normalOutput() {
	echo "::: Pi-hole version is ${PHVERSION} (Latest version is ${PHVERSIONLATEST:-${DEFAULT}})"
	echo "::: Web-Admin version is ${WEBVERSION} (Latest version is ${WEBVERSIONLATEST:-${DEFAULT}})"
}

webOutput() {
	for var in "$1"; do
		case "${var}" in
			"-l" | "--latest"    ) echo "${WEBVERSIONLATEST:-${DEFAULT}}";;
			"-c" | "--current"   ) echo "${WEBVERSION}";;
			"-h" | "--hash"      ) echo "${WEBHASH}";;
			*                    ) echo "::: Invalid Option!"; exit 1;
		esac
	done
}

coreOutput() {
	for var in "$1"; do
		case "${var}" in
			"-l" | "--latest"    ) echo "${PHVERSIONLATEST:-${DEFAULT}}";;
			"-c" | "--current"   ) echo "${PHVERSION}";;
			"-h" | "--hash"      ) echo "${PHHASH}";;
			*                    ) echo "::: Invalid Option!"; exit 1;
		esac
	done
}

helpFunc() {
	cat << EOM
:::
::: Show Pi-hole/Web Admin versions
:::
::: Usage: pihole -v [ -a | -p ] [ -l | -c ]
:::
::: Options:
:::  -a, --admin          Show both current and latest versions of web admin
:::  -p, --pihole         Show both current and latest versions of Pi-hole core files
:::  -l, --latest         (Only after -a | -p) Return only latest version
:::  -c, --current        (Only after -a | -p) Return only current version
:::  -h, --help           Show this help dialog
:::
EOM
	exit 0
}

getLocalPHVersion
getLocalWebVersion

if [[ $# = 0 ]]; then
	normalOutput
fi

for var in "$1"; do
	case "${var}" in
	"-a" | "--admin"     ) shift; webOutput "$@";;
	"-p" | "--pihole"    ) shift; coreOutput "$@" ;;
	"-h" | "--help"      ) helpFunc;;
	esac
done
