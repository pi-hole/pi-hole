#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Generates pihole_debug.log to be used for troubleshooting.
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.



set -o pipefail

######## GLOBAL VARS ########
VARSFILE="/etc/pihole/setupVars.conf"
DEBUG_LOG="/var/log/pihole_debug.log"
DNSMASQFILE="/etc/dnsmasq.conf"
DNSMASQCONFDIR="/etc/dnsmasq.d/*"
LIGHTTPDFILE="/etc/lighttpd/lighttpd.conf"
LIGHTTPDERRFILE="/var/log/lighttpd/error.log"
GRAVITYFILE="/etc/pihole/gravity.list"
WHITELISTFILE="/etc/pihole/whitelist.txt"
BLACKLISTFILE="/etc/pihole/blacklist.txt"
ADLISTFILE="/etc/pihole/adlists.list"
PIHOLELOG="/var/log/pihole.log"
WHITELISTMATCHES="/tmp/whitelistmatches.list"

TIMEOUT=60
# Header info and introduction
cat << EOM
::: Beginning Pi-hole debug at $(date)!
:::
::: This process collects information from your Pi-hole, and optionally uploads
::: it to a unique and random directory on tricorder.pi-hole.net.
:::
::: NOTE: All log files auto-delete after 48 hours and ONLY the Pi-hole developers
::: can access your data via the given token. We have taken these extra steps to
::: secure your data and will work to further reduce any personal information gathered.
:::
::: Please read and note any issues, and follow any directions advised during this process.
EOM

# Ensure the file exists, create if not, clear if exists.
truncate --size=0 "${DEBUG_LOG}"
chmod 644 ${DEBUG_LOG}
chown "$USER":pihole ${DEBUG_LOG}

source ${VARSFILE}

### Private functions exist here ###
log_write() {
    echo "${1}" >> "${DEBUG_LOG}"
}

log_echo() {
  case ${1} in
    -n)
      echo -n ":::       ${2}"
      log_write "${2}"
      ;;
    -r)
      echo ":::       ${2}"
      log_write "${2}"
      ;;
    -l)
      echo "${2}"
      log_write "${2}"
      ;;
     *)
      echo ":::  ${1}"
      log_write "${1}"
  esac
}

header_write() {
  log_echo ""
  log_echo "${1}"
  log_write ""
}

file_parse() {
    while read -r line; do
		  if [ ! -z "${line}" ]; then
			  [[ "${line}" =~ ^#.*$  || ! "${line}" ]] && continue
				log_write "${line}"
			fi
		done < "${1}"
		log_write ""
}

block_parse() {
  log_write "${1}"
}

lsof_parse() {
  local user
  local process

  user=$(echo ${1} | cut -f 3 -d ' ' | cut -c 2-)
  process=$(echo ${1} | cut -f 2 -d ' ' | cut -c 2-)
  [[ ${2} -eq ${process} ]] \
  && echo ":::       Correctly configured." \
  || log_echo ":::       Failure: Incorrectly configured daemon."

  log_write "Found user ${user} with process ${process}"
}


version_check() {
  header_write "Detecting Installed Package Versions:"

  local error_found
  error_found=0

	local pi_hole_ver="$(cd /etc/.pihole/ && git describe --tags --abbrev=0)" \
	&& log_echo -r "Pi-hole: $pi_hole_ver" || (log_echo "Pi-hole git repository not detected." && error_found=1)
	local admin_ver="$(cd /var/www/html/admin && git describe --tags --abbrev=0)" \
	&& log_echo -r "WebUI: $admin_ver" || (log_echo "Pi-hole Admin Pages git repository not detected." && error_found=1)
	local light_ver="$(lighttpd -v |& head -n1 | cut -d " " -f1)" \
	&& log_echo -r "${light_ver}" || (log_echo "lighttpd not installed." && error_found=1)
	local php_ver="$(php -v |& head -n1)" \
	&& log_echo -r "${php_ver}" || (log_echo "PHP not installed." && error_found=1)

	(local pi_hole_branch="$(cd /etc/.pihole/ && git rev-parse --abbrev-ref HEAD)" && log_echo -r "Pi-hole branch:  ${pi_hole_branch}") || log_echo "Unable to obtain Pi-hole branch"
	(local pi_hole_rev="$(cd /etc/.pihole/ && git describe --long --dirty --tags)" && log_echo -r "Pi-hole rev:     ${pi_hole_rev}") || log_echo "Unable to obtain Pi-hole revision"

	(local admin_branch="$(cd /var/www/html/admin && git rev-parse --abbrev-ref HEAD)" && log_echo -r "AdminLTE branch: ${admin_branch}") || log_echo "Unable to obtain AdminLTE branch"
	(local admin_rev="$(cd /var/www/html/admin && git describe --long --dirty --tags)" && log_echo -r "AdminLTE rev:    ${admin_rev}") || log_echo "Unable to obtain AdminLTE revision"

	return "${error_found}"
}

dir_check() {
  header_write "Detecting contents of ${1}:"
  for file in $1*; do
    header_write "File ${file} found"
    echo -n ":::       Parsing..."
    file_parse "${file}"
    echo "done"
  done
  echo ":::"
}

files_check() {
  #Check non-zero length existence of ${1}
  header_write "Detecting existence of ${1}:"
  local search_file="${1}"
  if [[ -s ${search_file} ]]; then
     echo -n ":::       File exists, parsing..."
     file_parse "${search_file}"
     echo "done"
     return 0
  else
    log_echo "${1} not found!"
    return 1
  fi
  echo ":::"
}

source_file() {
  local file_found=$(files_check "${1}") \
   && (source "${1}" &> /dev/null && echo "${file_found} and was successfully sourced") \
   || log_echo -l "${file_found} and could not be sourced"
}

distro_check() {
  local soft_fail
  header_write "Detecting installed OS Distribution"
  soft_fail=0
	local distro="$(cat /etc/*release)" && block_parse "${distro}" || (log_echo "Distribution details not found." && soft_fail=1)
	return "${soft_fail}"
}

processor_check() {
  header_write "Checking processor variety"
  log_write $(uname -m) && return 0 || return 1
}

ipv6_check() {
  # Check if system is IPv6 enabled, for use in other functions
  if [[ $IPV6_ADDRESS ]]; then
    ls /proc/net/if_inet6 &>/dev/null
    return 0
  else
    return 1
  fi
}

ip_check() {
  local protocol=${1}
  local gravity=${2}

  local ip_addr_list="$(ip -${protocol} addr show dev ${PIHOLE_INTERFACE} | awk -F ' ' '{ for(i=1;i<=NF;i++) if ($i ~ '/^inet/') print $(i+1) }')"
  if [[ -n ${ip_addr_list} ]]; then
    log_write "IPv${protocol} on ${PIHOLE_INTERFACE}"
    log_write "Gravity configured for: ${2:-NOT CONFIGURED}"
    log_write "----"
    log_write "${ip_addr_list}"
    echo ":::       IPv${protocol} addresses located on ${PIHOLE_INTERFACE}"
    ip_ping_check ${protocol}
    return $(( 0 + $? ))
  else
    log_echo "No IPv${protocol} found on ${PIHOLE_INTERFACE}"
    return 1
  fi
}

ip_ping_check() {
  local protocol=${1}
  local cmd

  if [[ ${protocol} == "6" ]]; then
    cmd="ping6"
    g_addr="2001:4860:4860::8888"
  else
    cmd="ping"
    g_addr="8.8.8.8"
  fi

  local ip_def_gateway=$(ip -${protocol} route | grep default | cut -d ' ' -f 3)
  if [[ -n ${ip_def_gateway} ]]; then
    echo -n ":::        Pinging default IPv${protocol} gateway: "
    if ! ping_gateway="$(${cmd} -q -W 3 -c 3 -n ${ip_def_gateway} -I ${PIHOLE_INTERFACE} | tail -n 3)"; then
     echo "Gateway did not respond."
     return 1
    else
      echo "Gateway responded."
      log_write "${ping_gateway}"
    fi
    echo -n ":::        Pinging Internet via IPv${protocol}: "
    if ! ping_inet="$(${cmd} -q -W 3 -c 3 -n ${g_addr} -I ${PIHOLE_INTERFACE} | tail -n 3)"; then
      echo "Query did not respond."
      return 1
    else
      echo "Query responded."
      log_write "${ping_inet}"
    fi
  else
    log_echo "        No gateway detected."
  fi
  return 0
}

port_check() {
  local lsof_value

  lsof_value=$(lsof -i ${1}:${2} -FcL | tr '\n' ' ') \
  && lsof_parse "${lsof_value}" "${3}" \
  || log_echo "Failure: IPv${1} Port not in use"
}

daemon_check() {
  # Check for daemon ${1} on port ${2}
	header_write "Daemon Process Information"

	echo ":::     Checking ${2} port for ${1} listener."

	if [[ ${IPV6_READY} ]]; then
	  port_check 6 "${2}" "${1}"
  fi
	lsof_value=$(lsof -i 4:${2} -FcL | tr '\n' ' ') \
    port_check 4 "${2}" "${1}"
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
	log_write "Upstream Servers:"
	dig +short chaos txt servers.bind >> ${DEBUG_LOG}
	log_write ""
}

checkProcesses() {
	header_write "Processes Check"

	echo ":::     Logging status of lighttpd, dnsmasq and pihole-FTL..."
	PROCESSES=( lighttpd dnsmasq pihole-FTL )
	for i in "${PROCESSES[@]}"; do
		log_write ""
		log_write "${i}"
		log_write " processes status:"
		systemctl -l status "${i}" >> "${DEBUG_LOG}"
	done
	log_write ""
}

debugLighttpd() {
  echo ":::     Checking for necessary lighttpd files."
  files_check "${LIGHTTPDFILE}"
  files_check "${LIGHTTPDERRFILE}"
  echo ":::"
}

countdown() {
  local tuvix
  tuvix=${TIMEOUT}
  printf "::: Logging will automatically teminate in %s seconds\n" "${TIMEOUT}"
  while [ $tuvix -ge 1 ]
  do
    printf ":::\t%s seconds left. " "${tuvix}"
    if [[ -z "${WEBCALL}" ]]; then
      printf "\r"
    else
      printf "\n"
    fi
    sleep 5
    tuvix=$(( tuvix - 5 ))
  done
}
### END FUNCTIONS ###

# Gather version of required packages / repositories
version_check || echo "REQUIRED FILES MISSING"
# Check for newer setupVars storage file
source_file "/etc/pihole/setupVars.conf"
# Gather information about the running distribution
distro_check || echo "Distro Check soft fail"
# Gather processor type
processor_check || echo "Processor Check soft fail"

ip_check 6 ${IPV6_ADDRESS}
ip_check 4 ${IPV4_ADDRESS}

daemon_check lighttpd http
daemon_check dnsmasq domain
daemon_check pihole-FTL 4711
checkProcesses
testResolver
debugLighttpd

files_check "${DNSMASQFILE}"
dir_check "${DNSMASQCONFDIR}"
files_check "${WHITELISTFILE}"
files_check "${BLACKLISTFILE}"
files_check "${ADLISTFILE}"


header_write "Analyzing gravity.list"

	gravity_length=$(grep -c ^ "${GRAVITYFILE}") \
	&& log_write "${GRAVITYFILE} is ${gravity_length} lines long." \
	|| log_echo "Warning: No gravity.list file found!"

header_write "Analyzing pihole.log"

  pihole_length=$(grep -c ^ "${PIHOLELOG}") \
  && log_write "${PIHOLELOG} is ${pihole_length} lines long." \
  || log_echo "Warning: No pihole.log file found!"

  pihole_size=$(du -h "${PIHOLELOG}" | awk '{ print $1 }') \
  && log_write "${PIHOLELOG} is ${pihole_size}." \
  || log_echo "Warning: No pihole.log file found!"


# Continuously append the pihole.log file to the pihole_debug.log file
dumpPiHoleLog() {
	trap '{ echo -e "\n::: Finishing debug write from interrupt... Quitting!" ; exit 1; }' INT
	echo "::: "
	echo "::: --= User Action Required =--"
	echo -e "::: Try loading a site that you are having trouble with now from a client web browser.. \n:::\t(Press CTRL+C to finish logging.)"
	header_write "pihole.log"
	if [ -e "${PIHOLELOG}" ]; then
	# Dummy process to use for flagging down tail to terminate
	  countdown &
		tail -n0 -f --pid=$! "${PIHOLELOG}" >> ${DEBUG_LOG}
	else
		log_write "No pihole.log file found!"
		printf ":::\tNo pihole.log file found!\n"
	fi
}

# Anything to be done after capturing of pihole.log terminates
finalWork() {
  local tricorder
	echo "::: Finshed debugging!"
	echo "::: The debug log can be uploaded to tricorder.pi-hole.net for sharing with developers only."
	if [[ "${AUTOMATED}" ]]; then
	  echo "::: Debug script running in automated mode, uploading log to tricorder..."
	  tricorder=$(cat /var/log/pihole_debug.log | nc tricorder.pi-hole.net 9999)
	else
	  read -r -p "::: Would you like to upload the log? [y/N] " response
	  case ${response} in
		  [yY][eE][sS]|[yY])
			  tricorder=$(cat /var/log/pihole_debug.log | nc tricorder.pi-hole.net 9999)
			  ;;
		  *)
			  echo "::: Log will NOT be uploaded to tricorder."
			  ;;
	  esac
  fi
	# Check if tricorder.pi-hole.net is reachable and provide token.
	if [ -n "${tricorder}" ]; then
		echo "::: ---=== Your debug token is : ${tricorder} Please make a note of it. ===---"
		echo "::: Contact the Pi-hole team with your token for assistance."
		echo "::: Thank you."
	else
		echo "::: There was an error uploading your debug log."
		echo "::: Please try again or contact the Pi-hole team for assistance."
	fi
		echo "::: A local copy of the Debug log can be found at : /var/log/pihole_debug.log"
}

trap finalWork EXIT

### Method calls for additional logging ###
dumpPiHoleLog
