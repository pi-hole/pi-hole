#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Generates pihole_debug.log to be used for troubleshooting.
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

set -o pipefail

######## GLOBAL VARS ########
DEBUG_LOG="/var/log/pihole_debug.log"
DNSMASQFILE="/etc/dnsmasq.conf"
PIHOLECONFFILE="/etc/dnsmasq.d/01-pihole.conf"
LIGHTTPDFILE="/etc/lighttpd/lighttpd.conf"
LIGHTTPDERRFILE="/var/log/lighttpd/error.log"
GRAVITYFILE="/etc/pihole/gravity.list"
HOSTSFILE="/etc/hosts"
WHITELISTFILE="/etc/pihole/whitelist.txt"
BLACKLISTFILE="/etc/pihole/blacklist.txt"
ADLISTSFILE="/etc/pihole/adlists.list"
PIHOLELOG="/var/log/pihole.log"
WHITELISTMATCHES="/tmp/whitelistmatches.list"

# Header info and introduction
cat << EOM
::: Beginning Pi-hole debug at $(date)!
::: This debugging process will collect information from your running configuration,
::: and optionally upload the generated log to a unique and random directory on
::: Termbin.com. NOTE: All log files auto-delete after 1 month and you are the only
::: person who is given the unique URL. Please consider where you post this link.
:::
EOM

# Ensure the file exists, create if not, clear if exists.
if [ ! -f "${DEBUG_LOG}" ]; then
	touch ${DEBUG_LOG}
	chmod 644 ${DEBUG_LOG}
	chown "$USER":root ${DEBUG_LOG}
else
	truncate -s 0 ${DEBUG_LOG}
fi

### Private functions exist here ###
log_write() {
	echo "${1}" >> "${DEBUG_LOG}"
}

header_write() {
  echo "" >> "${DEBUG_LOG}"
  echo "::: ${1}" >> "${DEBUG_LOG}"
  echo "" >> "${DEBUG_LOG}"
}

log_echo() {
  echo ":::       ${1}"
  log_write "${1}"
}

version_check() {
  header_write "Installed Package Versions"
	echo ":::     Detecting Pi-hole installed versions."

	local pi_hole_ver="$(cd /etc/.pihole/ && git describe --tags --abbrev=0)" \
	&& log_echo "Pi-hole: $pi_hole_ver" || log_echo "Pi-hole git repository not detected."
	local admin_ver="$(cd /var/www/html/admin && git describe --tags --abbrev=0)" \
	&& log_echo "WebUI: $admin_ver" || log_echo "Pi-hole Admin Pages git repository not detected."
	local light_ver="$(lighttpd -v |& head -n1 | cut -d " " -f1)" \
	&& log_echo "${light_ver}" || log_echo "lighttpd not installed."
	local php_ver="$(php -v |& head -n1)" \
	&& log_echo "${php_ver}" || log_echo "PHP not installed."
	echo ":::"
}

files_check() {
  header_write "File Check"

  #Check non-zero length existence of ${1}
  echo ":::     Detecting existence of ${1}..."
  local search_file=/etc/pihole/"${1}"
  if [[ -s ${search_file} ]]; then
    log_echo "/etc/pihole/${1} exists!"
    source "${search_file}" &> /dev/null && log_echo "Successfully sourced ${search_file}" || log_echo "Could not source ${search_file}"
    while read -r line; do
		  if [ ! -z "${line}" ]; then
			  [[ "${line}" =~ ^#.*$ ]] && continue
				log_write "${line}"
			fi
		done < "${search_file}"
	else
    log_echo "/etc/pihole/${1} not found!"
  fi
  echo ":::"
}

distro_check() {
  header_write "Installed OS Distribution"

	echo ":::     Checking installed OS Distribution release."
	local distro="$(cat /etc/*release)" && log_write "${distro}" || log_write "Distribution details not found."
	echo ":::"
}

ip_check() {
	header_write "IP Address Information"
	# Get the current interface for Internet traffic
	local IPv6_temp_interface=$(ip -6 r | grep default | cut -d ' ' -f 5)
	# If declared in setupVars.conf use it, otherwise defer to default
	# http://stackoverflow.com/questions/2013547/assigning-default-values-to-shell-variables-with-a-single-command-in-bash
	local IPv6_interface=${piholeInterface:-$IPv6_temp_interface}

	echo ":::     Collecting local IP info."
	local IPv4_addr_list="$(ip a | awk -F " " '{ for(i=1;i<=NF;i++) if ($i == "inet") print $(i+1) }')" \
	&& (log_write "${IPv4_addr_list}" && echo ":::       IPv4 addresses located") || log_echo "No IPv4 addresses found."

	local IPv6_addr_list="$(ip a | awk -F " " '{ for(i=1;i<=NF;i++) if ($i == "inet6") print $(i+1) }')" \
	&& (log_write "${IPv6_addr_list}" && echo ":::       IPv6 addresses located") || log_echo "No IPv6 addresses found."


	echo ":::     Locating default gateway and checking connectivity"
	local IPv4_def_gateway=$(ip r | grep default | cut -d ' ' -f 3)
	if [[ $? = 0 ]]; then
		echo ":::     Pinging default IPv4 gateway..."
		local IPv4_def_gateway_check="$(ping -q -w 3 -c 3 -n "${IPv4_def_gateway}" | tail -n3)" \
		&& echo ":::       IPv4 Default Gateway Responded." || echo ":::       IPv4 Default Gateway did not respond."
		log_write "${IPv4_def_gateway_check}"

		echo ":::     Pinging Internet via IPv4..."
		local IPv4_inet_check="$(ping -q -w 5 -c 3 -n 8.8.8.8 | tail -n3)" \
		&& echo ":::       IPv4 Internet query responded." || echo ":::       IPv4 Internet query did not respond."
		log_write "${IPv4_inet_check}"
	fi

	local IPv6_def_gateway=$(ip -6 r | grep default | cut -d ' ' -f 3)
	if [[ $? = 0 ]]; then
		echo ":::     Pinging default IPv6 gateway..."
		local IPv6_def_gateway_check="$(ping6 -q -W 3 -c 3 -n "${IPv6_def_gateway}" -I "${IPv6_interface}"| tail -n3)" \
		&& echo ":::       IPv6 Default Gateway Responded." || echo ":::       IPv6 Default Gateway did not respond."
    log_write "${IPv6_def_gateway_check}"

		echo ":::     Pinging Internet via IPv6..."
		local IPv6_inet_check=$(ping6 -q -W 3 -c 3 -n 2001:4860:4860::8888 -I "${IPv6_interface}"| tail -n3) \
		&& echo ":::       IPv6 Internet query responded." || echo ":::       IPv6 Internet query did not respond."
	else
		IPv6_inet_check="No IPv6 Gateway Detected"
	fi
	log_write "${IPv6_inet_check}"
	log_write ""
	echo ":::"
}

hostnameCheck() {
	header_write "Hostname Information"

	echo ":::     Writing locally configured hostnames to logfile"
	# Write the hostname output to compare against entries in /etc/hosts, which is logged next
	log_write "This Pi-hole is: $(hostname)"

	echo ":::     Writing hosts file to debug log..."
	log_write "###              Hosts              ###"

	if [ -e "${HOSTSFILE}" ]; then
		cat "${HOSTSFILE}" >> ${DEBUG_LOG}
		log_write ""
	else
		log_write "No hosts file found!"
		printf ":::\tNo hosts file found!\n"
	fi
}

portCheck() {
	header_write "Open Port Information"

	echo ":::     Detecting local server port 80 and 53 processes."

	lsof -i :80 >> ${DEBUG_LOG}
	lsof -i :53 >> ${DEBUG_LOG}
	log_write ""
}

testResolver() {
	header_write "Resolver Functions Check"

	# Find a blocked url that has not been whitelisted.
	TESTURL="doubleclick.com"
	if [ -s "${WHITELISTMATCHES}" ]; then
		while read -r line; do
			CUTURL=${line#*" "}
			if [ "${CUTURL}" != "Pi-Hole.IsWorking.OK" ]; then
				while read -r line2; do
					CUTURL2=${line2#*" "}
					if [ "${CUTURL}" != "${CUTURL2}" ]; then
						TESTURL="${CUTURL}"
						break 2
					fi
				done < "${WHITELISTMATCHES}"
			fi
		done < "${GRAVITYFILE}"
	fi

	log_write "Resolution of ${TESTURL} from Pi-hole:"
	LOCALDIG=$(dig "${TESTURL}" @127.0.0.1)
	if [[ $? = 0 ]]; then
		log_write "${LOCALDIG}"
	else
		log_write "Failed to resolve ${TESTURL} on Pi-hole"
	fi
	log_write ""


	log_write "Resolution of ${TESTURL} from 8.8.8.8:"
	REMOTEDIG=$(dig "${TESTURL}" @8.8.8.8)
	if [[ $? = 0 ]]; then
		log_write "${REMOTEDIG}"
	else
		log_write "Failed to resolve ${TESTURL} on 8.8.8.8"
	fi
	log_write ""

	log_write "Pi-hole dnsmasq specific records lookups"
	log_write "Cache Size:"
	dig +short chaos txt cachesize.bind >> ${DEBUG_LOG}
	log_write "Insertions count:"
	dig +short chaos txt insertions.bind >> ${DEBUG_LOG}
	log_write "Evictions count:"
	dig +short chaos txt evictions.bind >> ${DEBUG_LOG}
	log_write "Misses count:"
	dig +short chaos txt misses.bind >> ${DEBUG_LOG}
	log_write "Hits count:"
	dig +short chaos txt hits.bind >> ${DEBUG_LOG}
	log_write "Auth count:"
	dig +short chaos txt auth.bind >> ${DEBUG_LOG}
	log_write "Upstream Servers:"
	dig +short chaos txt servers.bind >> ${DEBUG_LOG}
	log_write ""
}

checkProcesses() {
	header_write "Processes Check"

	echo ":::     Logging status of lighttpd and dnsmasq..."
	PROCESSES=( lighttpd dnsmasq )
	for i in "${PROCESSES[@]}"; do
		log_write ""
		log_write -n "${i}"
		log_write " processes status:"
		systemctl -l status "${i}" >> "${DEBUG_LOG}"
	done
	log_write ""
}

debugLighttpd() {
	header_write "lighttpd.conf"

	if [ -e "${LIGHTTPDFILE}" ]; then
		while read -r line; do
			if [ ! -z "${line}" ]; then
				[[ "${line}" =~ ^#.*$ ]] && continue
				log_write "${line}"
			fi
		done < "${LIGHTTPDFILE}"
		log_write ""
	else
		log_write "No lighttpd.conf file found!"
		printf ":::\tNo lighttpd.conf file found\n"
	fi

	if [ -e "${LIGHTTPDERRFILE}" ]; then
		log_write ""
		log_write "::: lighttpd error.log"
		log_write ""

		cat "${LIGHTTPDERRFILE}" >> ${DEBUG_LOG}
	else
		log_write "No lighttpd error.log file found!"
		printf ":::\tNo lighttpd error.log file found\n"
	fi
	log_write ""
}

### END FUNCTIONS ###

version_check
files_check "setupVars.conf"
distro_check
ip_check
hostnameCheck
portCheck
checkProcesses
testResolver
debugLighttpd

echo "::: Writing dnsmasq.conf to debug log..."
header_write "Dnsmasq configuration"
if [ -e "${DNSMASQFILE}" ]; then
	#cat $DNSMASQFILE >> $DEBUG_LOG
	while read -r line; do
		if [ ! -z "${line}" ]; then
			[[ "${line}" =~ ^#.*$ ]] && continue
			log_write "${line}"
		fi
	done < "${DNSMASQFILE}"
	log_write ""
else
	log_write "No dnsmasq.conf file found!"
	printf ":::\tNo dnsmasq.conf file found!\n"
fi

echo "::: Writing 01-pihole.conf to debug log..."
header_write "01-pihole.conf"

if [ -e "${PIHOLECONFFILE}" ]; then
	while read -r line; do
		if [ ! -z "${line}" ]; then
			[[ "${line}" =~ ^#.*$ ]] && continue
			log_write "${line}"
		fi
	done < "${PIHOLECONFFILE}"
	log_write
else
	log_write "No 01-pihole.conf file found!"
	printf ":::\tNo 01-pihole.conf file found\n"
fi

echo "::: Writing size of gravity.list to debug log..."
header_write "gravity.list"

if [ -e "${GRAVITYFILE}" ]; then
	wc -l "${GRAVITYFILE}" >> ${DEBUG_LOG}
	log_write ""
else
	log_write "No gravity.list file found!"
	printf ":::\tNo gravity.list file found\n"
fi


### Pi-hole application specific logging ###
echo "::: Writing whitelist to debug log..."
header_write "Whitelist"
if [ -e "${WHITELISTFILE}" ]; then
	cat "${WHITELISTFILE}" >> ${DEBUG_LOG}
	log_write
else
	log_write "No whitelist.txt file found!"
	printf ":::\tNo whitelist.txt file found!\n"
fi

echo "::: Writing blacklist to debug log..."
header_write "Blacklist"
if [ -e "${BLACKLISTFILE}" ]; then
	cat "${BLACKLISTFILE}" >> ${DEBUG_LOG}
	log_write
else
	log_write "No blacklist.txt file found!"
	printf ":::\tNo blacklist.txt file found!\n"
fi

echo "::: Writing adlists.list to debug log..."
header_write "adlists.list"
if [ -e "${ADLISTSFILE}" ]; then
	while read -r line; do
		if [ ! -z "${line}" ]; then
			[[ "${line}" =~ ^#.*$ ]] && continue
			log_write "${line}"
		fi
	done < "${ADLISTSFILE}"
	log_write
else
	log_write "No adlists.list file found... using adlists.default!"
	printf ":::\tNo adlists.list file found... using adlists.default!\n"
fi


# Continuously append the pihole.log file to the pihole_debug.log file
dumpPiHoleLog() {
	trap '{ echo -e "\n::: Finishing debug write from interrupt... Quitting!" ; exit 1; }' INT
	echo -e "::: Writing current Pi-hole traffic to debug log...\n:::\tTry loading any/all sites that you are having trouble with now... \n:::\t(Press ctrl+C to finish)"
	header_write "pihole.log"
	if [ -e "${PIHOLELOG}" ]; then
		while true; do
			tail -f "${PIHOLELOG}" >> ${DEBUG_LOG}
			log_write ""
		done
	else
		log_write "No pihole.log file found!"
		printf ":::\tNo pihole.log file found!\n"
	fi
}

# Anything to be done after capturing of pihole.log terminates
finalWork() {
	echo "::: Finshed debugging!"
	echo "::: The debug log can be uploaded to Termbin.com for easier sharing."
	read -r -p "::: Would you like to upload the log? [y/N] " response
	case ${response} in
		[yY][eE][sS]|[yY])
			TERMBIN=$(cat /var/log/pihole_debug.log | nc termbin.com 9999)
			;;
		*)
			echo "::: Log will NOT be uploaded to Termbin."
			;;
	esac

	# Check if termbin.com is reachable. When it's not, point to local log instead
	if [ -n "${TERMBIN}" ]; then
		echo "::: Debug log can be found at : ${TERMBIN}"
	else
		echo "::: Debug log can be found at : /var/log/pihole_debug.log"
	fi
}

trap finalWork EXIT

### Method calls for additional logging ###
dumpPiHoleLog
