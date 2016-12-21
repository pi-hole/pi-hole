#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# shows version numbers
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

# Flags:
latest=false
current=false

DEFAULT="-1"

normalOutput() {
	piholeVersion=$(cd /etc/.pihole/ && git describe --tags --abbrev=0)
	webVersion=$(cd /var/www/html/admin/ && git describe --tags --abbrev=0)

	piholeVersionLatest=$(curl -s https://api.github.com/repos/pi-hole/pi-hole/releases/latest | grep -Po '"tag_name":.*?[^\\]",' |  perl -pe 's/"tag_name": "//; s/^"//; s/",$//')
	webVersionLatest=$(curl -s https://api.github.com/repos/pi-hole/AdminLTE/releases/latest | grep -Po '"tag_name":.*?[^\\]",' |  perl -pe 's/"tag_name": "//; s/^"//; s/",$//')

	echo "::: Pi-hole version is ${piholeVersion} (Latest version is ${piholeVersionLatest:-${DEFAULT}})"
	echo "::: Web-Admin version is ${webVersion} (Latest version is ${webVersionLatest:-${DEFAULT}})"
}

webOutput() {
	for var in "$@"; do
		case "${var}" in
			"-l" | "--latest"    ) latest=true;;
			"-c" | "--current"   ) current=true;;
			*                    ) echo "::: Invalid Option!"; exit 1;
		esac
	done

	if [[ "${latest}" == true && "${current}" == false ]]; then
		webVersionLatest=$(curl -s https://api.github.com/repos/pi-hole/AdminLTE/releases/latest | grep -Po '"tag_name":.*?[^\\]",' |  perl -pe 's/"tag_name": "//; s/^"//; s/",$//')
		echo "${webVersionLatest:--1}"
	elif [[ "${latest}" == false && "${current}" == true ]]; then
		webVersion=$(cd /var/www/html/admin/ && git describe --tags --abbrev=0)
		echo "${webVersion}"
	else
		webVersion=$(cd /var/www/html/admin/ && git describe --tags --abbrev=0)
		webVersionLatest=$(curl -s https://api.github.com/repos/pi-hole/AdminLTE/releases/latest | grep -Po '"tag_name":.*?[^\\]",' |  perl -pe 's/"tag_name": "//; s/^"//; s/",$//')
		echo "::: Web-Admin version is ${webVersion} (Latest version is ${webVersionLatest:-${DEFAULT}})"
	fi
}

coreOutput() {
	for var in "$@"; do
		case "${var}" in
			"-l" | "--latest"    ) latest=true;;
			"-c" | "--current"   ) current=true;;
			*                    ) echo "::: Invalid Option!"; exit 1;
		esac
	done

	if [[ "${latest}" == true && "${current}" == false ]]; then
		piholeVersionLatest=$(curl -s https://api.github.com/repos/pi-hole/pi-hole/releases/latest | grep -Po '"tag_name":.*?[^\\]",' |  perl -pe 's/"tag_name": "//; s/^"//; s/",$//')
		echo "${piholeVersionLatest:--1}"
	elif [[ "${latest}" == false && "${current}" == true ]]; then
		piholeVersion=$(cd /etc/.pihole/ && git describe --tags --abbrev=0)
		echo "${piholeVersion}"
	else
		piholeVersion=$(cd /etc/.pihole/ && git describe --tags --abbrev=0)
		piholeVersionLatest=$(curl -s https://api.github.com/repos/pi-hole/pi-hole/releases/latest | grep -Po '"tag_name":.*?[^\\]",' |  perl -pe 's/"tag_name": "//; s/^"//; s/",$//')
		echo "::: Pi-hole version is ${piholeVersion} (Latest version is ${piholeVersionLatest:-${DEFAULT}})"
	fi
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
