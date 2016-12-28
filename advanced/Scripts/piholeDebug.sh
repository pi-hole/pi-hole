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
readonly PIHOLE_DIR="/etc/pihole"
readonly PIHOLE_GIT_DIR="/etc/.pihole"
readonly ADMIN_GIT_DIR="/var/www/html/admin"
readonly LOG_DIR="/var/log"

readonly VARS="$PIHOLE_DIR/setupVars.conf"

readonly AD_LIST="$PIHOLE_DIR/adlists.list"
readonly GRAVITY_LIST="$PIHOLE_DIR/gravity.list"
readonly BLACKLIST="$PIHOLE_DIR/blacklist.txt"
readonly WHITELIST="$PIHOLE_DIR/whitelist.txt"

readonly DNSMASQ_CONF="/etc/dnsmasq.conf"
readonly DNSMASQ_PH_CONF="/etc/dnsmasq.d/01-pihole.conf"
readonly LIGHTTPD_CONF="/etc/lighttpd/lighttpd.conf"

readonly LIGHTTPD_ERR_LOG="$LOG_DIR/lighttpd/error.log"
readonly PI_HOLE_LOG="$LOG_DIR/pihole.log"

readonly WHITELIST_MATCHES="/tmp/whitelistmatches.list"

DEBUG_LOG="$LOG_DIR/pihole_debug.log"
TIMEOUT=60
MAJOR_ERRORS=0
MINOR_ERRORS=0
IPV6_ENABLED=""
IPV4_ENABLED=""

declare -A ERRORS

log_write() {
   printf "%b" "${1}" >&3
}

log_echo() {
  local arg="${1}"
  local message="${2}"

  case "${arg}" in
    -n)
      printf "%b" "${message}"
      log_write "${message}"
      ;;
     *)
      printf ":::%b" "${arg}"
      log_write "${arg}"
  esac
}

header_write() {
  log_echo "\n"
  log_echo "\t${1}\n"
}

file_parse() {
    # Read file input and write directly to log
    local file=${1}

    while read -r line; do
      if [ ! -z "${line}" ]; then
        [[ "${line}" =~ ^#.*$  || ! "${line}" ]] && continue
        log_write "\t\t${line}\n"
      fi
    done < "${file}"
}

block_parse() {
    local file=${1}

    while read -r line; do
      if [ ! -z "${line}" ]; then
        [[ "${line}" =~ ^#.*$  || ! "${line}" ]] && continue
        log_write "\t${line}\n"
      fi
    done <<< "${file}"
    log_write "\n"
}

repository_test() {
  header_write "Checking for local repositories:"

  local pi_hole_tag
  local pi_hole_hash
  local pi_hole_branch
  local admin_tag
  local admin_hash
  local admin_branch
  local error_count
  local cur_dir

  cur_dir="${PWD}"

  if [[ -d "${PIHOLE_GIT_DIR}" ]]; then
    cd "${PIHOLE_GIT_DIR}" || ERRORS+=(['CORE REPOSITORY DAMAGED']=major)
    pi_hole_tag="$(git describe --tags --abbrev=0 2>/dev/null)" \
    || ERRORS+=(['CORE REPOSITORY DAMAGED']=major)
    pi_hole_hash=":$(git log --pretty=format:'%h' -n 1))"
    pi_hole_branch="($(git branch | grep '^\*')"
  else
    ERRORS+=(['CORE REPOSITORY DAMAGED']=major)
  fi

  if [[ -d "${ADMIN_GIT_DIR}" ]]; then
    cd "${ADMIN_GIT_DIR}" || ERRORS+=(['WEBADMIN REPOSITORY DAMAGED']=major)
    admin_tag="$(git describe --tags --abbrev=0 2>/dev/null)" \
    || ERRORS+=(['WEBADMIN REPOSITORY DAMAGED']=major)
    admin_hash=":$(git log --pretty=format:'%h' -n 1))"
    admin_branch="($(git branch | grep '^\*')"
  else
    ERRORS+=(['WEBADMIN REPOSITORY DAMAGED']=major)
  fi

  log_echo "\tPi-hole Core Version: ${pi_hole_tag:-"git repository not detected"} ${pi_hole_branch}${pi_hole_hash}\n"
  log_echo "\tPi-hole WebUI Version: ${admin_tag:-"git repository not detected"} ${admin_branch}${admin_hash}\n"

  cd "${cur_dir}" || echo "You can't go home again."

  error_count=${#ERRORS[@]}
  if (( ! error_count != 0 )); then
    log_echo "\tSUCCESS: All repositories located.\n"
  fi
  return "$error_count"
}

package_test() {
  header_write "Detecting Installed Package Versions:"

  local light_ver
  local php_ver
  local error_count

  which lighttpd &>/dev/null \
  || ERRORS+=(['MISSING LIGHTTPD EXECUTABLE']=major) \
  && light_ver="$(lighttpd -v 2> /dev/null \
                | awk -F "/" '/lighttpd/ {print $2}' \
                | awk -F "-" '{print $1}')"
  which php &>/dev/null \
  || ERRORS+=(['MISSING PHP PROCESSOR']=major) \
  && php_ver="$(php -v 2> /dev/null \
                | awk '/cli/ {print $2}')"


  log_echo "\t\tLighttpd Webserver Version: ${light_ver:-"not located"}\n"
  log_echo "\t\tPHP Processor Version: ${php_ver:-"not located"}\n"

  error_count=${#ERRORS[@]}
  if (( ! error_count != 0 )); then
    log_echo "\tSUCCESS: All packages located.\n"
  fi
  return "$error_count"
}

files_check() {
  header_write "Detecting existence of ${1}"
  local search_file="${1}"

  if find "${search_file}" &>/dev/null
   then
     file_parse "${search_file}"
     return 0
  else
    log_write="\tnot found!\n"
    return=1
  fi
}

source_file() {
  if files_check "${1}"; then
    # shellcheck source=/dev/null
    source "${1}" &> /dev/null
  else
    log_echo "\t\t\tand could not be sourced\n"
    return 1
  fi
}

distro_check() {
  header_write "Detecting installed OS distribution"
  local error_found
  local distro
  local name

  distro="$(cat /etc/*release)"
  error_found=$?
  if [[ "${distro}" ]]; then
   name=$(awk -F '=' '/PRETTY_NAME/ {print $2}' <<< "${distro}")
   log_write "\t${name}\n"
  else
    log_echo "Distribution details not found."
  fi
  return "${error_found}"
}

processor_check() {
  header_write "Checking processor variety"
  log_write "\t$(uname -m)\n"
}

ipv6_enabled_test() {
  # Check if system is IPv6 enabled, for use in other functions
  if [[ "${IPV6_ADDRESS}" ]]; then
    if [[ -f /proc/net/if_inet6 ]]; then
      IPV6_ENABLED="true"
    fi
  fi
}

ip_test() {
  local protocol_version=${1}
  local IP_interface
  local IP_address_list
  local IP_defaut_gateway
  local IP_def_gateway_check
  local IP_inet_check
  local dns_server=${2}

  header_write "Testing IPv${protocol_version} interface"

  # If declared in setupVars.conf use it, otherwise defer to default
  IP_interface=${PIHOLE_INTERFACE:-$(ip -"${protocol_version}" r | grep default | cut -d ' ' -f 5)}
  IP_address_list="$(ip -"${protocol_version}" addr show | sed -e's/^.*inet* \([^ ]*\)\/.*$/\1/;t;d')"
  IP_defaut_gateway=$(ip -"${protocol_version}" route | grep default | cut -d ' ' -f 3)

  if [[ "${IP_address_list}" ]]; then
    log_echo "\t\tIP addresses found\n"
    log_write "${IP_address_list}\n"
    if [[ "${IP_defaut_gateway}" ]]; then
      printf ":::\t\tPinging default gateway: "
      IP_def_gateway_check="$(ping -q -w 3 -c 3 -n "${IP_defaut_gateway}"  -I "${IP_interface}" | tail -n3)"
      if [[ "${IP_def_gateway_check}" ]]; then
        printf "Gateway responded.\n"
        printf ":::\t\tPinging Internet via IPv4: "
        IP_inet_check="$(ping -q -w 5 -c 3 -n "${dns_server}" -I "${IP_interface}" | tail -n3)"
        if [[ "${IP_inet_check}" ]]; then
          printf "Query responded.\n"
        else
          printf "Query did not respond.\n"
        fi
        log_write "${IP_inet_check}\n"
      else
        printf "Gateway did not respond.\n"
      fi
      log_write "${IP_def_gateway_check}\n"
    else
      log_echo "No Gateway Detected"
    fi
  else
    log_echo "\t\tAddresses not found.\n"
  fi

}

lsof_parse() {
  local user
  local process

  user=$(echo "${1}" | cut -f 3 -d ' ' | cut -c 2-)
  process=$(echo "${1}" | cut -f 2 -d ' ' | cut -c 2-)
  if [[ ${2} -eq ${process} ]]; then
    echo ":::       Correctly configured."
  else
    log_echo ":::       Failure: Incorrectly configured daemon."
  fi
  log_write "Found user ${user} with process ${process}"
}

port_check() {
  local lsof_value

  lsof_value=$(lsof -i "${1}":"${2}" -FcL | tr '\n' ' ')
  if [[ "${lsof_value}" ]]; then
    lsof_parse "${lsof_value}" "${3}"
  else
    log_echo "Failure: IPv${1} Port not in use"
  fi
}

daemon_check() {
  # Check for daemon ${1} on port ${2}
  header_write "Daemon Process Information"

  echo ":::     Checking ${2} port for ${1} listener."

  if [[ "${IPV6_ENABLED}" ]]; then
    port_check 6 "${2}" "${1}"
  fi
  port_check 4 "${2}" "${1}"
}

resolve_and_log(){
  local resolver=${1}
  local test_domain=${2}
  local scope=${3}

  dig=$(dig "${test_domain}" @"${resolver}" +short)
  if [[ "${dig}" ]]; then
    log_write "\t${resolver} found ${test_domain} at ${dig}\n"
    if [[ "${scope}" != "remote" ]]; then
      log=$(grep "${test_domain}" "${PI_HOLE_LOG}")
      block_parse "${log}"
    fi
  else
    log_write "\tFailed to resolve ${test_domain} on Pi-hole\n"
  fi
}

resolver_test() {
  header_write "Checking Pi-hole DNS Resolver."

  local black_domain
  local rand_domain
  local remote_dig

  rand_domain=$(shuf -n 1 "${GRAVITY_LIST}" | awk -F " " '{print $2}')
  black_domain="${rand_domain:-"doubleclick.com"}"

  rand_domain=$(shuf -n 1 "${WHITELIST}")
  white_domain="tricorder.pihole.net"

  resolve_and_log 127.0.0.1 "${black_domain}" local
  resolve_and_log 127.0.0.1 "${white_domain}" local

  resolve_and_log 8.8.8.8 "${black_domain}" remote
  resolve_and_log 8.8.8.8 "${white_domain}" remote

  log_write "\tPi-hole dnsmasq specific records lookups\n"
  log_write "\tUpstream Servers:\n"
  upstreams=$(dig +short chaos txt servers.bind)
  log_write "\t${upstreams}"
  log_write ""
}

process_test() {
  header_write "Checking for necessary daemon processes:"

  local processes
  processes=( lighttpd dnsmasq )
  for i in "${processes[@]}"; do
    status=$(systemctl show "${i}" --property=ActiveState) &> /dev/null
    log_write "\t\t${i} $status\n"
  done
}

debugLighttpd() {
  header_write "Checking for necessary lighttpd files."
  files_check "${LIGHTTPD_CONF}"
  files_check "${LIGHTTPD_ERR_LOG}"
  echo ":::"
}

countdown() {
  tuvix=${TIMEOUT}
  printf "::: Logging will automatically teminate in ${TIMEOUT} seconds\n"
  while [ $tuvix -ge 1 ]
  do
    printf ":::\t${tuvix} seconds left. \r"
    sleep 5
    tuvix=$(( tuvix - 5 ))
  done
}

dumpPiHoleLog() {
  trap 'echo -e "\n::: Finishing debug write from interrupt..." ; finalWork' SIGINT
  echo "::: "
  printf ":::\t\t\t--= User Action Required =--\n"
  printf ":::\tTry loading a site that you are having trouble with from a client web browser.\n"
  printf ":::\t(Press CTRL+C to finish logging.)"
  header_write "pihole.log"
  if [ -e "${PI_HOLE_LOG}" ]; then
    countdown &
      tail -f -n0 --pid=$! "${PI_HOLE_LOG}" >&4
  else
    log_write "No pihole.log file found!"
    printf ":::\tNo pihole.log file found!\n"
  fi
}

final_error_handler() {
  printf "***\n"
  log_echo "***\t${MAJOR_ERRORS} Major Errors Detected\n"
  log_echo "***\t${MINOR_ERRORS} Minor Errors Detected\n"
  if [[ "${MAJOR_ERRORS}" -gt 0 ]] || [[ "${MINOR_ERRORS}" -gt 0 ]]; then
    printf "***\tFor immediate support, please visit https://discourse.pi-hole.net\n"
    printf "***\tand read the FAQ and Wiki sections to find fixes for common errors.\n"
    printf "***\n"
  fi
}

log_prep () {
  local file="${1}"
  local user="${2}"

  truncate --size=0 "$file" &> /dev/null || { DEBUG_LOG=""; return 1; }
  chmod 644 "${file}"
  chown "${user}":root "${file}"
  DEBUG_LOG="${file}"
  cp /proc/$$/fd/3 "$DEBUG_LOG"
}

debug_log_parse(){
  while read -r line; do
    if [[ ! -z "${line}" ]]; then
      if $(echo "${line}" | egrep -q 'cached|gravity')
      then
        log_write "\t\t${line}\n"
      fi
    fi
  done < /proc/$$/fd/4
}

finalWork() {
  local tricorder
  printf ":::\tFinshed debugging!"

  final_error_handler

  debug_log_parse
  log_prep "${DEBUG_LOG}" "$USER"

  if [[ ! "$DEBUG_LOG" ]]; then
    printf ":::\tWARNING: No local log available, please select upload when instructed\n"
    printf ":::\tto provide a copy to the developers.\n"
  else
    printf ":::\tA local copy of the Debug log can be found at : %s\n"  "${DEBUG_LOG}"
  fi
  if which nc &> /dev/null && nc -w5 tricorder.pi-hole.net 9999; then
    printf ":::\tThe debug log can be uploaded to tricorder.pi-hole.net for sharing with developers only.\n"
    read -r -p "::: Would you like to upload the log? [y/N] " response
    case ${response} in
      [yY][eE][sS]|[yY])
        tricorder=$(nc -w 10 tricorder.pi-hole.net 9999 < /var/log/pihole_debug.log)
        ;;
      *)
        printf ":::\tLog will NOT be uploaded to tricorder.\n"
        ;;
    esac

    if [[ "${tricorder}" ]]; then
      echo ":::"
      log_echo "::: Your debug token is : ${tricorder}"
      echo ":::"
      echo "::: Please contact the Pi-hole team with your token for assistance."
      echo "::: Thank you."
    fi
  else
    echo "::: There was an error uploading your debug log."
    echo "::: Please try again or contact the Pi-hole team for assistance."
  fi
exit 0
}

count_gravity() {
header_write "Analyzing gravity.list"

  gravity_length=$(echo "${GRAVITY_LIST}" | wc -l)
  if [[ "${gravity_length}" ]]; then
    log_write "${GRAVITY_LIST} is ${gravity_length} lines long."
  else
    log_echo "Warning: No gravity.list file found!"
  fi
}

error_handler() {
  echo "***"
  log_echo -n "***\t${#ERRORS[@]} Errors found\n"

  for K in "${!ERRORS[@]}";
  do
    log_echo -n "***\t\t${ERRORS[$K]} -- ${K}\n"
    if [[ ${ERRORS[$K]} == "major" ]]; then
      MAJOR_ERRORS=$((MAJOR_ERRORS+1))
    else
      MINOR_ERRORS=$((MINOR_ERRORS+1))
    fi
    unset ERRORS["$K"]
  done
}

script_header () {

# Header info and introduction
cat << EOM
:::
::: Beginning Pi-hole debug at $(date)!
:::
::: This process collects information from your Pi-hole, and optionally uploads
::: it to a unique and random directory on tricorder.pi-hole.net.
:::
::: NOTE: All log files auto-delete after 24 hours and ONLY the Pi-hole developers
::: can access your data via the given token. We have taken these extra steps to
::: secure your data and will work to further reduce any personal information gathered.
:::
::: Please read and note any issues, and follow any directions advised during this process.
:::
EOM
}

main() {
# Create temporary file for log
templog=$(mktemp /tmp/pihole_temp.XXXXXX)
# Open handle for templog
exec 3>"$templog"
# Delete templog, but allow for addressing via file handle.
rm "$templog"

# Create temporary file for logdump
logdump=$(mktemp /tmp/pihole_temp.XXXXXX)
exec 4>"$logdump"
rm "$logdump"

# Welcome to the debugger
script_header

# Ensure the file exists, create if not, clear if exists, and debug to terminal if none of the above.
source_file "$VARS" || ERRORS+=(['SETUPVARS FILE MISSING']=major); error_handler

# Check for IPv6
ipv6_enabled_test

# Gather information about the running distribution
distro_check || echo "Distro Check soft fail"
# Gather processor type
processor_check || echo "Processor Check soft fail"

# Gather version of required packages / repositories
repository_test || error_handler
package_test || error_handler

if [[ "${IPV6_ENABLED}" ]]; then
  ip_test "6" "2001:4860:4860::8888"
fi
ip_test "4" "8.8.8.8"

daemon_check lighttpd http
daemon_check dnsmasq domain
process_test
resolver_test
debugLighttpd

files_check "${DNSMASQ_CONF}"
files_check "${DNSMASQ_PH_CONF}"
files_check "${WHITELIST}"
files_check "${BLACKLIST}"
files_check "${AD_LIST}"

count_gravity
dumpPiHoleLog
finalWork

}
main
