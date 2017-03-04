#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# shows version numbers
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# Flags:
latest=false
current=false

# Variables
DEFAULT="-1"
PHGITDIR="/etc/.pihole/"
WEBGITDIR="/var/www/html/admin/"

getLocalPHVersion(){
  # Get the tagged version of the local Pi-hole repository
  local version

  cd "${PHGITDIR}" || { PHVERSION="${DEFAULT}"; return -1; }
  version=$(git describe --tags --always || \
            echo "${DEFAULT}")
  if [[ "${version}" =~ ^v ]]; then
    PHVERSION="${version}"
  elif [[ "${version}" == "-1" ]]; then
    PHVERSION="ERROR"
  else
    PHVERSION="Untagged"
  fi
  return 0
}

WEBVERSION=$(cd /var/www/html/admin/ \
             && git describe --tags --always)

PHHASH=$(cd /etc/.pihole/ \
             && git rev-parse --short HEAD)
WEBHASH=$(cd /var/www/html/admin/ \
          && git rev-parse --short HEAD)

PHVERSIONLATEST=$(curl -s https://api.github.com/repos/pi-hole/pi-hole/releases/latest | \
                      grep -Po '"tag_name":.*?[^\\]",' | \
                      perl -pe 's/"tag_name": "//; s/^"//; s/",$//')
WEBVERSIONLATEST=$(curl -s https://api.github.com/repos/pi-hole/AdminLTE/releases/latest | \
                   grep -Po '"tag_name":.*?[^\\]",' | \
                   perl -pe 's/"tag_name": "//; s/^"//; s/",$//')

PHHASHLATEST=$(curl -s https://api.github.com/repos/pi-hole/pi-hole/commits/master | \
                   grep sha | \
                   head -n1 | \
                   awk -F ' ' '{ print $2}' | \
                   tr -cd '[[:alnum:]]._-')

WEBHASHLATEST=$(curl -s https://api.github.com/repos/pi-hole/AdminLTE/commits/master | \
                   grep sha | \
                   head -n1 | \
                   awk -F ' ' '{ print $2}' | \
                   tr -cd '[[:alnum:]]._-')


normalOutput() {
	echo "::: Pi-hole version is ${PHVERSION} (Latest version is ${PHVERSIONLATEST:-${DEFAULT}})"
	echo "::: Web-Admin version is ${WEBVERSION:-Untagged} (Latest version is ${WEBVERSIONLATEST:-${DEFAULT}})"
}

webOutput() {
	for var in "$@"; do
		case "${var}" in
			"-l" | "--latest"    ) echo "${WEBVERSIONLATEST:-${DEFAULT}}";;
			"-c" | "--current"   ) echo "${WEBVERSION:-Untagged}";;
			"-h" | "--hash"      ) echo "${WEBHASH}";;
			*                    ) echo "::: Invalid Option!"; exit 1;
		esac
	done
}

coreOutput() {
	for var in "$@"; do
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

if [[ $# = 0 ]]; then
	normalOutput
fi

for var in "$@"; do
	case "${var}" in
	"-a" | "--admin"     ) shift; webOutput "$@";;
	"-p" | "--pihole"    ) shift; coreOutput "$@" ;;
	"-h" | "--help"      ) helpFunc;;
	esac
done
