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
MAJOR_ERRORS=0
MINOR_ERRORS=0
IPV6_ENABLED=""
IPV4_ENABLED=""

declare -A ERRORS

log_write() {
   echo "${1}" >> "${DEBUG_LOG}"
}

log_echo() {
  local arg="${1}"
  local message="${2}"

  case "${arg}" in
    -n)
      printf "${message}"
      log_write "${message}"
      ;;
     *)
      printf ":::${arg}"
      log_write "${arg}"
  esac
}

header_write() {
  log_echo "\n"
  log_echo "\t${1}\n"
  log_echo "\n"
}

file_parse() {
    # Read file input and write directly to log
    local file=${1}

    while read -r line; do
      if [ ! -z "${line}" ]; then
        [[ "${line}" =~ ^#.*$  || ! "${line}" ]] && continue
        log_write "${line}"
      fi
    done < "${file}"
    log_write ""
}

repository_test() {
  header_write "Detecting Local Repositories:"

  local pi_hole_ver
  local admin_ver
  local error_count

  pi_hole_ver="$(git -C /etc/.pihole describe --tags --abbrev=0 2>/dev/null)" \
  || ERRORS+=(['CORE REPOSITORY DAMAGED']=major)
  admin_ver="$(git -C /var/www/html/admin describe --tags --abbrev=0 2>/dev/null)" \
  || ERRORS+=(['WEBADMIN REPOSITORY DAMAGED']=major)

  log_echo "\t\tPi-hole Core Version: ${pi_hole_ver:-"git repository not detected"}\n"
  log_echo "\t\tPi-hole WebUI Version: ${admin_ver:-"git repository not detected"}\n"

  error_count=${#ERRORS[@]}
  if (( error_count != 0 )); then
    return "$error_count"
  else
    log_echo "SUCCESS: All repositories located."
  fi
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
  if (( error_count != 0 )); then
    return "$error_count"
  else
    log_echo "\tSUCCESS: All packages located.\n"
  fi
}

files_check() {
  header_write "Detecting existence of ${1}:"
  local search_file="${1}"
  if [[ -s ${search_file} ]]; then
     log_echo "\tFile exists"
     file_parse "${search_file}"
     return 0
  else
    log_echo "\t\t${1} not found!\n"
    return 1
  fi
  #echo ":::"
}

source_file() {
  local file_found

  file_found=$(files_check "${1}")
  if [[ "${file_found}" ]]; then
    # shellcheck source=/dev/null
    source "${1}" &> /dev/null || echo "${file_found} and could not be sourced"
  fi
}

distro_check() {
  header_write "Detecting installed OS distribution:"
  local error_found
  local distro

  error_found=0
  distro="$(cat /etc/*release)"
  if [[ "${distro}" ]]; then
    log_write "${distro}"
  else
    log_echo "Distribution details not found."
    error_found=1
  fi
  return "${error_found}"
}

processor_check() {
  header_write "Checking processor variety"
  log_write "$(uname -m)"
}

ipv6_check() {
  # Check if system is IPv6 enabled, for use in other functions
  if [[ "${IPV6_ADDRESS}" ]]; then
    ls /proc/net/if_inet6 &>/dev/null && IPV6_ENABLED="true"
  fi
}

ip_check() {
  header_write "IP Address Information"

  local IPv6_interface
  local IPv4_interface
  local IPv6_address_list
  local IPv6_default_gateway
  local IPv6_def_gateway_check
  local IPv6_inet_check
  local IPv4_address_list
  local IPv4_defaut_gateway
  local IPv4_def_gateway_check
  local IPv4_inet_check

  # If declared in setupVars.conf use it, otherwise defer to default
  # http://stackoverflow.com/questions/2013547/assigning-default-values-to-shell-variables-with-a-single-command-in-bash

  if [[ "${IPV6_ENABLED}" ]]; then
    IPv6_address_list="$(ip a | awk -F " " '{ for(i=1;i<=NF;i++) if ($i == "inet6") print $(i+1) }')"
    IPv6_interface=${PIHOLE_INTERFACE:-$(ip -6 r | grep default | cut -d ' ' -f 5)}
    IPv6_default_gateway=$(ip -6 r | grep default | cut -d ' ' -f 3)

    if [[ "${IPv6_address_list}" ]]; then
      log_echo "IPv6 addresses found"
      log_write "${IPv6_address_list}"
      if [[ -n ${IPv6_default_gateway} ]]; then
        echo -n ":::      Pinging default IPv6 gateway: "
        IPv6_def_gateway_check="$(ping6 -q -W 3 -c 3 -n "${IPv6_default_gateway}" -I "${IPv6_interface}"| tail -n3)"
        if [[ -n ${IPv6_def_gateway_check} ]]; then
          echo "Gateway Responded."
          echo -n ":::      Pinging Internet via IPv6: "
          IPv6_inet_check=$(ping6 -q -W 3 -c 3 -n 2001:4860:4860::8888 -I "${IPv6_interface}"| tail -n3)
          if [[ ${IPv6_inet_check} ]]; then
            echo "Query responded."
          else
            echo "Query did not respond."
          fi
          log_write "${IPv6_inet_check}"
        else
          echo "Gateway did not respond."
        fi
        log_write "${IPv6_def_gateway_check}"
      else
        log_echo "No IPv6 Gateway Detected"
      fi
    else
      log_echo "IPV6 addresses not found"
    fi
  fi

  IPv4_interface=${PIHOLE_INTERFACE:-$(ip r | grep default | cut -d ' ' -f 5)}
  IPv4_address_list="$(ip a | awk -F " " '{ for(i=1;i<=NF;i++) if ($i == "inet") print $(i+1) }')"
  IPv4_defaut_gateway=$(ip r | grep default | cut -d ' ' -f 3)

  if [[ "${IPv4_address_list}" ]]; then
    log_echo "IPv4 addresses found"
    log_write "${IPv4_address_list}"
    if [[ "${IPv4_defaut_gateway}" ]]; then
      echo -n ":::      Pinging default IPv4 gateway: "
      IPv4_def_gateway_check="$(ping -q -w 3 -c 3 -n "${IPv4_defaut_gateway}"  -I "${IPv4_interface}" | tail -n3)"
      if [[ "${IPv4_def_gateway_check}" ]]; then
        echo "Gateway responded."
        echo -n ":::      Pinging Internet via IPv4: "
        IPv4_inet_check="$(ping -q -w 5 -c 3 -n 8.8.8.8 -I "${IPv4_interface}" | tail -n3)"
        if [[ "${IPv4_inet_check}" ]]; then
          echo "Query responded."
        else
          echo "Query did not respond."
        fi
        log_write "${IPv4_inet_check}"
      else
        echo "Gateway did not respond."
      fi
      log_write "${IPv4_def_gateway_check}"
    else
      log_echo "No IPv4 Gateway Detected"
    fi
  else
    log_echo "IPv4 addresses not found."
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

testResolver() {
  header_write "Checking Pi-hole DNS Resolver."

  local test_domain
  local rand_domain
  local local_dig
  local remote_dig


  # Find a blocked url.
  rand_domain=$(shuf -n 1 $GRAVITY_LIST | awk -F " " '{print $2}')
  test_domain="${rand_domain:-"doubleclick.com"}"

  printf ":::\tResolving %s via Pi-hole:\n" "${test_domain}"
  local_dig=$(dig "${test_domain}" @127.0.0.1 +short)
  if [[ "${local_dig}" ]]; then
    log_write "Pi-hole reports ${test_domain} is at ${local_dig}"
  else
    log_write "Failed to resolve ${test_domain} on Pi-hole"
  fi
  log_write ""


  printf ":::\tResolving %s via 8.8.8.8:\n" "${test_domain}"
  remote_dig=$(dig "${test_domain}" @8.8.8.8 +short | tail -n1)
  if [[ "${remote_dig}" ]]; then
    log_write "Remote DNS reports ${test_domain} is at ${remote_dig}"
  else
    log_write "Failed to resolve ${test_domain} on 8.8.8.8"
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
  header_write "Checkig for neccssary daemon processes:"

  local processes
  echo ":::     Logging status of lighttpd and dnsmasq..."
  processes=( lighttpd dnsmasq )
  for i in "${processes[@]}"; do
    log_write ""
    log_write "${i}"
    log_write " processes status:"
    systemctl -l status "${i}" >> "${DEBUG_LOG}"
  done
  log_write ""
}

debugLighttpd() {
  header_write "Checking for necessary lighttpd files."
  files_check "${LIGHTTPD_CONF}"
  files_check "${LIGHTTPD_ERR_LOG}"
  echo ":::"
}

dumpPiHoleLog() {
  trap 'echo -e "\n::: Finishing debug write from interrupt..." ; break' SIGINT
  echo "::: "
  echo "::: --= User Action Required =--"
  echo -e "::: Try loading a site that you are having trouble with now from a client web browser.. \n:::\t(Press CTRL+C to finish logging.)"
  header_write "pihole.log"
  if [ -e "${PI_HOLE_LOG}" ]; then
    while true; do
      tail -f "${PI_HOLE_LOG}" >> ${DEBUG_LOG}
      log_write ""
    done
  else
    log_write "No pihole.log file found!"
    printf ":::\tNo pihole.log file found!\n"
  fi
}

finalWork() {
  local tricorder
  echo "::: Finshed debugging!"

  if which nc &> /dev/null && nc -w5 tricorder.pi-hole.net 9999; then
    echo "::: The debug log can be uploaded to tricorder.pi-hole.net for sharing with developers only."
    read -r -p "::: Would you like to upload the log? [y/N] " response
    case ${response} in
      [yY][eE][sS]|[yY])
        tricorder=$(nc -w 10 tricorder.pi-hole.net 9999 < /var/log/pihole_debug.log)
        ;;
      *)
        echo "::: Log will NOT be uploaded to tricorder."
        ;;
    esac

    if [[ "${tricorder}" ]]; then
      echo ":::"
      log_echo "::: Your debug token is : ${tricorder}"
      echo ":::"
      echo "::: Please contact the Pi-hole team with your token for assistance."
      echo "::: Thank you."
    else
      echo "::: No debug logs will be transmitted..."
    fi
  else
    echo "::: There was an error uploading your debug log."
    echo "::: Please try again or contact the Pi-hole team for assistance."
  fi
echo "::: A local copy of the Debug log can be found at : ${DEBUG_LOG}"
exit
}

count_gravity() {
header_write "Analyzing gravity.list"

  gravity_length=$(wc -l "${GRAVITY_LIST}")
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
      ((MAJOR_ERRORS++))
    else
      ((MINOR_ERRORS++))
    fi
    unset ERRORS["$K"]
  done
}

final_error_handler() {
  printf "***\n"
  log_echo -l "***   ${#ERRORS[@]} Errors found"

  for K in "${!ERRORS[@]}";
  do
    log_echo -l "***       ${ERRORS[$K]} -- ${K}"
  done
  echo "*** Please upload a copy of your log and contact support."
  echo "*** For immediate support, please visit https://discourse.pi-hole.net"
  echo "*** and read the FAQ and Wiki sections to find fixes for common errors."
  echo "***"
  finalWork
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

log_prep () {
  local file="${1}"
  local user="${2}"

  truncate --size=0 "${file}" &> /dev/null\
  || DEBUG_LOG="/dev/null"
  chmod 644 "${file}" || return 1
  chown "${user}":root "${file}"
}

main() {

# Ensure the file exists, create if not, clear if exists, and debug to terminal if none of the above.
log_prep "${DEBUG_LOG}" "$USER" || echo ":::   Unable to open logfile, debugging to console only."
script_header
source_file "$VARS" || echo "REQUIRED FILE MISSING"

# Check for IPv6
ipv6_check

# Gather information about the running distribution
distro_check || echo "Distro Check soft fail"
# Gather processor type
processor_check || echo "Processor Check soft fail"

# Gather version of required packages / repositories
repository_test || error_handler
package_test || error_handler

ip_check

daemon_check lighttpd http
daemon_check dnsmasq domain
checkProcesses
testResolver
debugLighttpd

files_check "${DNSMASQ_CONF}"
files_check "${DNSMASQ_PH_CONF}"
files_check "${WHITELIST}"
files_check "${BLACKLIST}"
files_check "${AD_LIST}"

count_gravity
dumpPiHoleLog

trap finalWork EXIT
}
main
