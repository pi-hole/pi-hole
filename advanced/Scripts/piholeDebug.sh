#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Generates pihole_debug.log to be used for troubleshooting.
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.


# causes a pipeline to produce a failure return code if any command errors.
# Normally, pipelines only return a failure if the last command errors.
# In combination with set -e, this will make your script exit if any command in a pipeline errors.
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
PIHOLEGITDIR="/etc/.pihole/"
ADMINGITDIR="/var/www/html/admin/"
WHITELISTMATCHES="/tmp/whitelistmatches.list"
readonly FTLLOG="/var/log/pihole-FTL.log"
coltable=/opt/pihole/COL_TABLE

if [[ -f ${coltable} ]]; then
  source ${coltable}
else
  COL_NC='\e[0m' # No Color
  COL_YELLOW='\e[1;33m'
  COL_LIGHT_PURPLE='\e[1;35m'
  COL_CYAN='\e[0;36m'
  TICK="[${COL_LIGHT_GREEN}✓${COL_NC}]"
  CROSS="[${COL_LIGHT_RED}✗${COL_NC}]"
  INFO="[i]"
  DONE="${COL_LIGHT_GREEN} done!${COL_NC}"
  OVER="\r\033[K"
fi

echo_succes_or_fail() {
  local message="${1}"
  if [ $? -eq 0 ]; then
    echo -e "   ${TICK} ${message}"
  else
    echo -e "   ${CROSS} ${message}"
  fi
}

initiate_debug() {
  # Clear the screen so the debug log is readable
  clear
  echo -e "${COL_LIGHT_PURPLE}*** [ INITIALIZING ]${COL_NC}"
  echo -e "   ${INFO} $(date "+%Y-%m-%d:%H:%M:%S") debug log has been initiated."
}

# This is a function for visually displaying the curent test that is being run.
# Accepts one variable: the name of what is being diagnosed
echo_current_diagnostic() {
  # Colors are used for visually distinguishing each test in the output
  echo -e "\n${COL_LIGHT_PURPLE}*** [ DIAGNOSING ]:${COL_NC} ${1}"
}

if_file_exists() {
  local file_to_test="${1}"
  # If the file is readable
  if [[ -r "${file_to_test}" ]]; then
    # Return success
    return 0
  else
    # Otherwise, return a failure
    return 1
  fi
}

get_distro_attributes() {
  # Put the current Internal Field Separator into another variable so it can be restored later
  OLD_IFS="$IFS"
  # Store the distro info in an array and make it global since the OS won't change,
  # but we'll keep it within the function for better unit testing
  IFS=$'\r\n' command eval 'distro_info=( $(cat /etc/*release) )'

  local distro_attribute
  for distro_attribute in "${distro_info[@]}"; do
    # Display the information with the ${INFO} icon
    # No need to show the support URLs so they are grepped out
    echo "   ${INFO} ${distro_attribute}" | grep -v "_URL" | tr -d '"'
  done
  # Set the IFS back to what it was
  IFS="$OLD_IFS"
}

diagnose_operating_system() {
  # Display the current test that is running
  echo_current_diagnostic "Operating system"

  # If there is a /etc/*release file, it's probably a supported operating system, so we can
  if_file_exists /etc/*release && \
    # display the attributes to the user
    get_distro_attributes || \
    # If it doesn't exist, it's not a system we currently support
    echo -e "   ${CROSS} ${COL_LIGHT_RED}Distribution unknown -- most likely you are on an unsupported platform and may run into issues.${COL_NC}
        ${INFO} ${COL_LIGHT_RED}Please see${COL_NC}: ${COL_CYAN}https://discourse.pi-hole.net/t/hardware-software-requirements/273${COL_NC}"
}

parse_file() {
  local filename="${1}"
  OLD_IFS="$IFS"
  IFS=$'\r\n' command eval 'file_info=( $(cat "${filename}") )'

  local file_lines
  for file_lines in "${file_info[@]}"; do
    # Display the information with the ${INFO} icon
    # No need to show the support URLs so they are grepped out
    echo "      ${INFO} ${file_lines}"
  done
  # Set the IFS back to what it was
  IFS="$OLD_IFS"
}

diagnose_setup_variables() {
  # Display the current test that is running
  echo_current_diagnostic "Setup variables"

  # If the variable file exists,
  if_file_exists "${VARSFILE}" && \
    # source it
    echo -e "   ${INFO} Sourcing ${VARSFILE}...";
    source ${VARSFILE};
    # and display a green check mark with ${DONE}
    echo_succes_or_fail "${VARSFILE} is readable and has been sourced." || \
    # Othwerwise, error out
    echo_succes_or_fail "${VARSFILE} is not readable.
        ${INFO} $(ls -l ${VARSFILE} 2>/dev/null)";
    parse_file "${VARSFILE}"
}

dir_check() {
  local directory="${1}"
  echo_current_diagnostic "contents of ${directory}"
  for filename in "${directory}"*; do
    if_file_exists "${filename}" && \
    echo_succes_or_fail "Files detected" || \
    echo_succes_or_fail "directory does not exist"
  done
}

list_files_in_dir() {
  local dir_to_parse="${1}"
  local filename
  files_found=( $(ls "${dir_to_parse}") )
  for each_file in "${files_found[@]}"; do
    # Display the information with the ${INFO} icon
    echo "      ${INFO} ${each_file}"
  done

}

check_dnsmasq_d() {
  local directory=/etc/dnsmasq.d
  dir_check "${directory}"
  list_files_in_dir "${directory}"
}

initiate_debug
diagnose_operating_system
diagnose_setup_variables
check_dnsmasq_d
