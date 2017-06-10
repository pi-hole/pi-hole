#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Generates pihole_debug.log to be used for troubleshooting.
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.


# -e option instructs bash to immediately exit if any command [1] has a non-zero exit status
# -u a reference to any variable you haven't previously defined
# with the exceptions of $* and $@ - is an error, and causes the program to immediately exit
# -o pipefail prevents errors in a pipeline from being masked. If any command in a pipeline fails,
# that return code will be used as the return code of the whole pipeline. By default, the
# pipeline's return code is that of the last command - even if it succeeds
set -o pipefail
#IFS=$'\n\t'

######## GLOBAL VARS ########
# These variables would normally be next to the other files
# but we need them to be first in order to get the colors needed for the script output
PIHOLE_SCRIPTS_DIRECTORY="/opt/pihole"
PIHOLE_COLTABLE_FILE="${PIHOLE_SCRIPTS_DIRECTORY}/COL_TABLE"

# These provide the colors we need for making the log more readable
if [[ -f ${PIHOLE_COLTABLE_FILE} ]]; then
  source ${PIHOLE_COLTABLE_FILE}
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

# FAQ URLs for use in showing the debug log
FAQ_UPDATE_PI_HOLE="${COL_CYAN}https://discourse.pi-hole.net/t/how-do-i-update-pi-hole/249${COL_NC}"
FAQ_CHECKOUT_COMMAND="${COL_CYAN}https://discourse.pi-hole.net/t/the-pihole-command-with-examples/738#checkout${COL_NC}"
FAQ_HARDWARE_REQUIREMENTS="${COL_CYAN}https://discourse.pi-hole.net/t/hardware-software-requirements/273${COL_NC}"
FAQ_GATEWAY="${COL_CYAN}https://discourse.pi-hole.net/t/why-is-a-default-gateway-important-for-pi-hole/3546${COL_NC}"
FAQ_ULA="${COL_CYAN}https://discourse.pi-hole.net/t/use-ipv6-ula-addresses-for-pi-hole/2127${COL_NC}"
FAQ_FTL_COMPATIBILITY="${COL_CYAN}https://github.com/pi-hole/FTL#compatibility-list${COL_NC}"

# Other URLs we may use
FORUMS_URL="${COL_CYAN}https://discourse.pi-hole.net${COL_NC}"
TRICORDER_CONTEST="${COL_CYAN}https://pi-hole.net/2016/11/07/crack-our-medical-tricorder-win-a-raspberry-pi-3/${COL_NC}"

# Port numbers used for uploading the debug log
TRICORDER_NC_PORT_NUMBER=9999
TRICORDER_SSL_PORT_NUMBER=9998

# Directories required by Pi-hole
# https://discourse.pi-hole.net/t/what-files-does-pi-hole-use/1684
CORE_GIT_DIRECTORY="/etc/.pihole"
CRON_D_DIRECTORY="/etc/cron.d"
DNSMASQ_D_DIRECTORY="/etc/dnsmasq.d"
PIHOLE_DIRECTORY="/etc/pihole"
PIHOLE_SCRIPTS_DIRECTORY="/opt/pihole"
BIN_DIRECTORY="/usr/local/bin"
RUN_DIRECTORY="/run"
LOG_DIRECTORY="/var/log"
WEB_SERVER_LOG_DIRECTORY="${LOG_DIRECTORY}/lighttpd"
WEB_SERVER_CONFIG_DIRECTORY="/etc/lighttpd"
HTML_DIRECTORY="/var/www/html"
WEB_GIT_DIRECTORY="${HTML_DIRECTORY}/admin"
BLOCK_PAGE_DIRECTORY="${HTML_DIRECTORY}/pihole"

# Files required by Pi-hole
# https://discourse.pi-hole.net/t/what-files-does-pi-hole-use/1684
PIHOLE_CRON_FILE="${CRON_D_DIRECTORY}/pihole"

PIHOLE_DNS_CONFIG_FILE="${DNSMASQ_D_DIRECTORY}/01-pihole.conf"
PIHOLE_DHCP_CONFIG_FILE="${DNSMASQ_D_DIRECTORY}/02-pihole-dhcp.conf"
PIHOLE_WILDCARD_CONFIG_FILE="${DNSMASQ_D_DIRECTORY}/03-wildcard.conf"

WEB_SERVER_CONFIG_FILE="${WEB_SERVER_CONFIG_DIRECTORY}/lighttpd.conf"

PIHOLE_DEFAULT_AD_LISTS="${PIHOLE_DIRECTORY}/adlists.default"
PIHOLE_USER_DEFINED_AD_LISTS="${PIHOLE_DIRECTORY}/adlists.list"
PIHOLE_BLACKLIST_FILE="${PIHOLE_DIRECTORY}/blacklist.txt"
PIHOLE_BLOCKLIST_FILE="${PIHOLE_DIRECTORY}/gravity.list"
PIHOLE_INSTALL_LOG_FILE="${PIHOLE_DIRECTORY}/install.log"
PIHOLE_RAW_BLOCKLIST_FILES=${PIHOLE_DIRECTORY}/list.*
PIHOLE_LOCAL_HOSTS_FILE="${PIHOLE_DIRECTORY}/local.list"
PIHOLE_LOGROTATE_FILE="${PIHOLE_DIRECTORY}/logrotate"
PIHOLE_SETUP_VARS_FILE="${PIHOLE_DIRECTORY}/setupVars.conf"
PIHOLE_WHITELIST_FILE="${PIHOLE_DIRECTORY}/whitelist.txt"

PIHOLE_COMMAND="${BIN_DIRECTORY}/pihole"
PIHOLE_COLTABLE_FILE="${BIN_DIRECTORY}/COL_TABLE"

FTL_PID="${RUN_DIRECTORY}/pihole-FTL.pid"
FTL_PORT="${RUN_DIRECTORY}/pihole-FTL.port"

PIHOLE_LOG="${LOG_DIRECTORY}/pihole.log"
PIHOLE_LOG_GZIPS=${LOG_DIRECTORY}/pihole.log.[0-9].*
PIHOLE_DEBUG_LOG="${LOG_DIRECTORY}/pihole_debug.log"
PIHOLE_FTL_LOG="${LOG_DIRECTORY}/pihole-FTL.log"

PIHOLE_WEB_SERVER_ACCESS_LOG_FILE="${WEB_SERVER_LOG_DIRECTORY}/access.log"
PIHOLE_WEB_SERVER_ERROR_LOG_FILE="${WEB_SERVER_LOG_DIRECTORY}/error.log"

# An array of operating system "pretty names" that we officialy support
# We can loop through the array at any time to see if it matches a value
SUPPORTED_OS=("Raspbian" "Ubuntu" "Fedora" "Debian" "CentOS")

# In a similar fashion, these are the folders Pi-hole needs
# https://discourse.pi-hole.net/t/what-files-does-pi-hole-use/1684
REQUIRED_DIRECTORIES=(${CORE_GIT_DIRECTORY}
${CRON_D_DIRECTORY}
${DNSMASQ_D_DIRECTORY}
${PIHOLE_DIRECTORY}
${PIHOLE_SCRIPTS_DIRECTORY}
${BIN_DIRECTORY}
${RUN_DIRECTORY}
${LOG_DIRECTORY}
${WEB_SERVER_LOG_DIRECTORY}
${WEB_SERVER_CONFIG_DIRECTORY}
${HTML_DIRECTORY}
${WEB_GIT_DIRECTORY}
${BLOCK_PAGE_DIRECTORY})

# These are the files Pi-hole needs--also stored in array for parsing through
# https://discourse.pi-hole.net/t/what-files-does-pi-hole-use/1684
REQUIRED_FILES=(${PIHOLE_CRON_FILE}
${PIHOLE_DNS_CONFIG_FILE}
${PIHOLE_DHCP_CONFIG_FILE}
${PIHOLE_WILDCARD_CONFIG_FILE}
${WEB_SERVER_CONFIG_FILE}
${PIHOLE_DEFAULT_AD_LISTS}
${PIHOLE_USER_DEFINED_AD_LISTS}
${PIHOLE_BLACKLIST_FILE}
${PIHOLE_BLOCKLIST_FILE}
${PIHOLE_INSTALL_LOG_FILE}
${PIHOLE_RAW_BLOCKLIST_FILES}
${PIHOLE_LOCAL_HOSTS_FILE}
${PIHOLE_LOGROTATE_FILE}
${PIHOLE_SETUP_VARS_FILE}
${PIHOLE_WHITELIST_FILE}
${PIHOLE_COMMAND}
${PIHOLE_COLTABLE_FILE}
${FTL_PID}
${FTL_PORT}
${PIHOLE_LOG}
${PIHOLE_LOG_GZIPS}
${PIHOLE_DEBUG_LOG}
${PIHOLE_FTL_LOG}
${PIHOLE_WEB_SERVER_ACCESS_LOG_FILE}
${PIHOLE_WEB_SERVER_ERROR_LOG_FILE})

source_setup_variables() {
  # Display the current test that is running
  log_write "\n${COL_LIGHT_PURPLE}*** [ INITIALIZING ]${COL_NC} Sourcing setup variables"
  # If the variable file exists,
  if_file_exists "${PIHOLE_SETUP_VARS_FILE}" && \
    log_write "${INFO} Sourcing ${PIHOLE_SETUP_VARS_FILE}...";
    # source it
    source ${PIHOLE_SETUP_VARS_FILE} || \
    # If it can't, show an error
    log_write "${PIHOLE_SETUP_VARS_FILE} ${COL_LIGHT_RED}does not exist or cannot be read.${COL_NC}"
}

make_temporary_log() {
  # Create temporary file for log
  TEMPLOG=$(mktemp /tmp/pihole_temp.XXXXXX)
  # Open handle 3 for templog
  # https://stackoverflow.com/questions/18460186/writing-outputs-to-log-file-and-console
  exec 3>"$TEMPLOG"
  # Delete templog, but allow for addressing via file handle.
  rm "$TEMPLOG"
}

log_write() {
  # echo arguments to both the log and the console
  echo -e "${@}" | tee -a /proc/$$/fd/3
}

copy_to_debug_log() {
  # Copy the contents of file descriptor 3 into the debug log so it can be uploaded to tricorder
  cat /proc/$$/fd/3 >> "${PIHOLE_DEBUG_LOG}"
}

echo_succes_or_fail() {
  # If the command was successful (a zero),
  if [[ $? -eq 0 ]]; then
    # Set the first argument passed to this function as a named variable for better readability
    local message="${1}"
    # show success
    log_write "${TICK} ${message}"
  else
    local message="${1}"
    # Otherwise, show a error
    log_write "${CROSS} ${message}"
  fi
}

initiate_debug() {
  # Clear the screen so the debug log is readable
  clear
  # Display that the debug process is beginning
  log_write "${COL_LIGHT_PURPLE}*** [ INITIALIZING ]${COL_NC}"
  # Timestamp the start of the log
  log_write "${INFO} $(date "+%Y-%m-%d:%H:%M:%S") debug log has been initiated."
}

# This is a function for visually displaying the curent test that is being run.
# Accepts one variable: the name of what is being diagnosed
# Colors do not show in the dasboard, but the icons do: [i], [✓], and [✗]
echo_current_diagnostic() {
  # Colors are used for visually distinguishing each test in the output
  # These colors do not show in the GUI, but the formatting will
  log_write "\n${COL_LIGHT_PURPLE}*** [ DIAGNOSING ]:${COL_NC} ${1}"
}

if_file_exists() {
  # Set the first argument passed to tihs function as a named variable for better readability
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

if_directory_exists() {
  # Set the first argument passed to tihs function as a named variable for better readability
  local directory_to_test="${1}"
  # If the file is readable
  if [[ -d "${directory_to_test}" ]]; then
    # Return success
    return 0
  else
    # Otherwise, return a failure
    return 1
  fi
}

compare_local_version_to_git_version() {
  # The git directory to check
  local git_dir="${1}"
  # The named component of the project (Core or Web)
  local pihole_component="${2}"
  # If we are checking the Core versions,
  if [[ "${pihole_component}" == "Core" ]]; then
    # We need to search for "Pi-hole" when using pihole -v
    local search_term="Pi-hole"
  elif [[ "${pihole_component}" == "Web" ]]; then
    local search_term="AdminLTE"
  fi
  # Display what we are checking
  echo_current_diagnostic "${pihole_component} version"
  # Store the error message in a variable in case we want to change and/or reuse it
  local error_msg="git status failed"
  # If the pihole git directory exists,
  if_directory_exists "${git_dir}" && \
    # move into it
    cd "${git_dir}" || \
    # If not, show an error
    log_write "${COL_LIGHT_RED}Could not cd into ${git_dir}$COL_NC"
    if git status &> /dev/null; then
      # The current version the user is on
      local remote_version=$(git describe --tags --abbrev=0);
      # What branch they are on
      local remote_branch=$(git rev-parse --abbrev-ref HEAD);
      # The commit they are on
      local remote_commit=$(git describe --long --dirty --tags --always)
      # echo this information out to the user in a nice format
      # If the current version matches what pihole -v produces, the user is up-to-date
      if [[ "${remote_version}" == "$(pihole -v | awk '/${search_term}/ {print $6}' | cut -d ')' -f1)" ]]; then
        log_write "${TICK} ${pihole_component}: ${COL_LIGHT_GREEN}${remote_version}${COL_NC}"
      # If not,
      else
        # echo the current version in yellow, signifying it's something to take a look at, but not a critical error
        # Also add a URL to an FAQ
        log_write "${INFO} ${pihole_component}: ${COL_YELLOW}${remote_version:-Untagged}${COL_NC} (${FAQ_UPDATE_PI_HOLE})"
      fi

      # If the repo is on the master branch, they are on the stable codebase
      if [[ "${remote_branch}" == "master" ]]; then
        # so the color of the text is green
        log_write "${INFO} Branch: ${COL_LIGHT_GREEN}${remote_branch}${COL_NC}"
      # If it is any other branch, they are in a developement branch
      else
        # So show that in yellow, signifying it's something to take a look at, but not a critical error
        log_write "${INFO} Branch: ${COL_YELLOW}${remote_branch:-Detached}${COL_NC} (${FAQ_CHECKOUT_COMMAND})"
      fi
        # echo the current commit
        log_write "${INFO} Commit: ${remote_commit}"
    # If git status failed,
    else
      # Return an error message
      log_write "${error_msg}"
      # and exit with a non zero code
      return 1
    fi
}

check_ftl_version() {
  local ftl_name="FTL"
  echo_current_diagnostic "${ftl_name} version"
  # Use the built in command to check FTL's version
  FTL_VERSION=$(pihole-FTL version)
  # Compare the current FTL version to the remote version
  if [[ "${FTL_VERSION}" == "$(pihole -v | awk '/FTL/ {print $6}' | cut -d ')' -f1)" ]]; then
    # If they are the same, FTL is up-to-date
    log_write "${TICK} ${ftl_name}: ${COL_LIGHT_GREEN}${FTL_VERSION}${COL_NC}"
  else
    # If not, show it in yellow, signifying there is an update
    log_write "${TICK} ${ftl_name}: ${COL_YELLOW}${FTL_VERSION}${COL_NC} (${FAQ_UPDATE_PI_HOLE})"
  fi
}

# Checks the core version of the Pi-hole codebase
check_component_versions() {
  # Check the Web version, branch, and commit
  compare_local_version_to_git_version "${CORE_GIT_DIRECTORY}" "Core"
  # Check the Web version, branch, and commit
  compare_local_version_to_git_version "${WEB_GIT_DIRECTORY}" "Web"
  # Check the FTL version
  check_ftl_version
}


get_program_version() {
  local program_name="${1}"
  local program_version
  echo_current_diagnostic "${program_name} version"
  case "${program_name}" in
    "lighttpd") program_version="$(${program_name} -v |& head -n1 | cut -d '/' -f2 | cut -d ' ' -f1)"
    ;;
    "dnsmasq") program_version="$(${program_name} -v |& head -n1 | awk '{print $3}')"
    ;;
    "php") program_version="$(${program_name} -v |& head -n1 | cut -d '-' -f1 | cut -d ' ' -f2)"
    ;;
    *) echo "Unrecognized program";
  esac
  # If the Web server does not have a version (the variable is empty)
  if [[ -z "${program_version}" ]]; then
    # Display and error
    log_write "${CROSS} ${COL_LIGHT_RED}${program_name} version could not be detected.${COL_NC}"
  else
    # Otherwise, display the version
    log_write "${INFO} ${program_version}"
  fi
}

# These are the most critical dependencies of Pi-hole, so we check for them
# and their versions, using the functions above.
check_critical_program_versions() {
  # Use the function created earlier and bundle them into one function that checks all the version numbers
  get_program_version "dnsmasq"
  get_program_version "lighttpd"
  get_program_version "php"
}

is_os_supported() {
  local os_to_check="${1}"
  the_os=$(echo ${os_to_check} | sed 's/ .*//')
  case "${the_os}" in
    "Raspbian") log_write "${TICK} ${COL_LIGHT_GREEN}${os_to_check}${COL_NC}";;
    "Ubuntu") log_write "${TICK} ${COL_LIGHT_GREEN}${os_to_check}${COL_NC}";;
    "Fedora") log_write "${TICK} ${COL_LIGHT_GREEN}${os_to_check}${COL_NC}";;
    "Debian") log_write "${TICK} ${COL_LIGHT_GREEN}${os_to_check}${COL_NC}";;
    "CentOS") log_write "${TICK} ${COL_LIGHT_GREEN}${os_to_check}${COL_NC}";;
      *) log_write "${CROSS} ${COL_LIGHT_RED}${os_to_check}${COL_NC} (${FAQ_HARDWARE_REQUIREMENTS})";
  esac
}

get_distro_attributes() {
  # Put the current Internal Field Separator into another variable so it can be restored later
  OLD_IFS="$IFS"
  # Store the distro info in an array and make it global since the OS won't change,
  # but we'll keep it within the function for better unit testing
  IFS=$'\r\n' command eval 'distro_info=( $(cat /etc/*release) )'

  # Set a named variable for better readability
  local distro_attribute
  # For each line found in an /etc/*release file,
  for distro_attribute in "${distro_info[@]}"; do
    # store the key in a variable
    local pretty_name_key=$(echo "${distro_attribute}" | grep "PRETTY_NAME" | cut -d '=' -f1)
    # we need just the OS PRETTY_NAME,
    if [[ "${pretty_name_key}" == "PRETTY_NAME" ]]; then
      # so save in in a variable when we find it
      PRETTY_NAME_VALUE=$(echo "${distro_attribute}" | grep "PRETTY_NAME" | cut -d '=' -f2- | tr -d '"')
      # then pass it as an argument that checks if the OS is supported
      is_os_supported "${PRETTY_NAME_VALUE}"
    else
      # Since we only need the pretty name, we can just skip over anything that is not a match
      :
    fi
  done
  # Set the IFS back to what it was
  IFS="$OLD_IFS"
}

diagnose_operating_system() {
  # error message in a variable so we can easily modify it later (or re-use it)
  local error_msg="Distribution unknown -- most likely you are on an unsupported platform and may run into issues."
  # Display the current test that is running
  echo_current_diagnostic "Operating system"

  # If there is a /etc/*release file, it's probably a supported operating system, so we can
  if_file_exists /etc/*release && \
    # display the attributes to the user from the function made earlier
    get_distro_attributes || \
    # If it doesn't exist, it's not a system we currently support and link to FAQ
    log_write "${CROSS} ${COL_LIGHT_RED}${error_msg}${COL_NC} (${FAQ_HARDWARE_REQUIREMENTS})"
}

processor_check() {
  echo_current_diagnostic "Processor"
  # Store the processor type in a variable
  PROCESSOR=$(uname -m)
  # If it does not contain a value,
  if [[ -z "${PROCESSOR}" ]]; then
    # we couldn't detect it, so show an error
    PROCESSOR=$(lscpu | awk '/Architecture/ {print $2}')
    log_write "${CROSS} ${COL_LIGHT_RED}${PROCESSOR}${COL_NC} has not been tested with FTL, but may still work: (${FAQ_FTL_COMPATIBILITY})"
  else
    # Check if the architecture is currently supported for FTL
    case "${PROCESSOR}" in
      "amd64") "${TICK} ${COL_LIGHT_GREEN}${PROCESSOR}${COL_NC}"
      ;;
      "armv6l") "${TICK} ${COL_LIGHT_GREEN}${PROCESSOR}${COL_NC}"
      ;;
      "armv6") "${TICK} ${COL_LIGHT_GREEN}${PROCESSOR}${COL_NC}"
      ;;
      "armv7l") "${TICK} ${COL_LIGHT_GREEN}${PROCESSOR}${COL_NC}"
      ;;
      "aarch64") "${TICK} ${COL_LIGHT_GREEN}${PROCESSOR}${COL_NC}"
      ;;
    # Otherwise, show the processor type
    *) log_write "${INFO} ${PROCESSOR}";
    esac
  fi
}

parse_setup_vars() {
  echo_current_diagnostic "Setup variables"
  if_file_exists "${PIHOLE_SETUP_VARS_FILE}" && \
    parse_file "${PIHOLE_SETUP_VARS_FILE}" || \
    log_write "${CROSS} ${COL_LIGHT_RED}Could not read ${PIHOLE_SETUP_VARS_FILE}.${COL_NC}"
}

does_ip_match_setup_vars() {
  # Check for IPv4 or 6
  local protocol="${1}"
  # IP address to check for
  local ip_address="${2}"
  # See what IP is in the setupVars.conf file
  local setup_vars_ip=$(cat ${PIHOLE_SETUP_VARS_FILE} | grep IPV${protocol}_ADDRESS | cut -d '=' -f2)
  # If it's an IPv6 address
  if [[ "${protocol}" == "6" ]]; then
    # Strip off the /
    if [[ "${ip_address%/*}" == "${setup_vars_ip}" ]]; then
      # if it matches, show it in green
      log_write "   ${COL_LIGHT_GREEN}${ip_address%/*}${COL_NC} matches the IP found in ${PIHOLE_SETUP_VARS_FILE}"
    else
      # otherwise show it in red with an FAQ URL
      log_write "   ${COL_LIGHT_RED}${ip_address%/*}${COL_NC} does not match the IP found in ${PIHOLE_SETUP_VARS_FILE} (${FAQ_ULA})"
    fi

  else
    # if the protocol isn't 6, it's 4 so no need to strip the CIDR notation
    # since it exists in the setupVars.conf that way
    if [[ "${ip_address}" == "${setup_vars_ip}" ]]; then
      # show in green if it matches
      log_write "   ${COL_LIGHT_GREEN}${ip_address}${COL_NC} matches the IP found in ${PIHOLE_SETUP_VARS_FILE}"
    else
      # otherwise show it in red
      log_write "   ${COL_LIGHT_RED}${ip_address}${COL_NC} does not match the IP found in ${PIHOLE_SETUP_VARS_FILE} (${FAQ_ULA})"
    fi
  fi
}

detect_ip_addresses() {
  # First argument should be a 4 or a 6
  local protocol=${1}
  # Use ip to show the addresses for the chosen protocol
  # Store the values in an arry so they can be looped through
  # Get the lines that are in the file(s) and store them in an array for parsing later
  declare -a ip_addr_list=( $(ip -${protocol} addr show dev ${PIHOLE_INTERFACE} | awk -F ' ' '{ for(i=1;i<=NF;i++) if ($i ~ '/^inet/') print $(i+1) }') )

  # If there is something in the IP address list,
  if [[ -n ${ip_addr_list} ]]; then
    # Local iterator
    local i
    # Display the protocol and interface
    log_write "${TICK} IPv${protocol} address(es) bound to the ${PIHOLE_INTERFACE} interface:"
    # Since there may be more than one IP address, store them in an array
    for i in "${!ip_addr_list[@]}"; do
      # For each one in the list, print it out
      does_ip_match_setup_vars "${protocol}" "${ip_addr_list[$i]}"
      # log_write "   ${ip_addr_list[$i]}"
    done
    log_write ""
  else
    # If there are no IPs detected, explain that the protocol is not configured
    log_write "${CROSS} ${COL_LIGHT_RED}No IPv${protocol} address(es) found on the ${PIHOLE_INTERFACE}${COL_NC} interace.\n"
    return 1
  fi
  # If the protocol is v6
  if [[ "${protocol}" == "6" ]]; then
    # let the user know that as long as there is one green address, things should be ok
    log_write "   ^ Please note that you may have more than one IP address listed."
    log_write "   As long as one of them is green, and it matches what is in ${PIHOLE_SETUP_VARS_FILE}, there is no need for concern.\n"
    log_write "   The link to the FAQ is for an issue that sometimes occurs when the IPv6 address changes, which is why we check for it.\n"
  fi
}

ping_ipv4_or_ipv6() {
  # Give the first argument a readable name (a 4 or a six should be the argument)
  local protocol="${1}"
  # If the protocol is 6,
  if [[ ${protocol} == "6" ]]; then
    # use ping6
    cmd="ping6"
    # and Google's public IPv6 address
    public_address="2001:4860:4860::8888"
  else
    # Otherwise, just use ping
    cmd="ping"
    # and Google's public IPv4 address
    public_address="8.8.8.8"
  fi
}

ping_gateway() {
  local protocol="${1}"
  ping_ipv4_or_ipv6 "${protocol}"
  # Check if we are using IPv4 or IPv6
  # Find the default gateway using IPv4 or IPv6
  local gateway
  gateway="$(ip -${protocol} route | grep default | cut -d ' ' -f 3)"

  # If the gateway variable has a value (meaning a gateway was found),
  if [[ -n "${gateway}" ]]; then
    log_write "${INFO} Default IPv${protocol} gateway: ${gateway}"
    # Let the user know we will ping the gateway for a response
    log_write "   * Pinging ${gateway}..."
    # Try to quietly ping the gateway 3 times, with a timeout of 3 seconds, using numeric output only,
    # on the pihole interface, and tail the last three lines of the output
    # If pinging the gateway is not successful,
    if ! ${cmd} -c 3 -W 2 -n ${gateway} -I ${PIHOLE_INTERFACE} >/dev/null; then
      # let the user know
      log_write "${CROSS} ${COL_LIGHT_RED}Gateway did not respond.${COL_NC} ($FAQ_GATEWAY)\n"
      # and return an error code
      return 1
    # Otherwise,
    else
      # show a success
      log_write "${TICK} ${COL_LIGHT_GREEN}Gateway responded.${COL_NC}"
      # and return a success code
      return 0
    fi
  fi
}

ping_internet() {
  local protocol="${1}"
  ping_ipv4_or_ipv6 "${protocol}"
  log_write "* Checking Internet connectivity via IPv${protocol}..."
  # Try to ping the address 3 times
  if ! ${cmd} -W 2 -c 3 -n ${public_address} -I ${PIHOLE_INTERFACE} >/dev/null; then
    # if it's unsuccessful, show an error
    log_write "${CROSS} ${COL_LIGHT_RED}Cannot reach the Internet.${COL_NC}\n"
    return 1
  else
    # Otherwise, show success
    log_write "${TICK} ${COL_LIGHT_GREEN}Query responded.${COL_NC}\n"
    return 0
  fi
}

compare_port_to_service_assigned() {
  local service_name="${1}"
  local resolver="dnsmasq"
  local web_server="lighttpd"
  local ftl="pihole-FT"
  if [[ "${service_name}" == "${resolver}" ]] || [[ "${service_name}" == "${web_server}" ]] || [[ "${service_name}" == "${ftl}" ]]; then
        # if port 53 is dnsmasq, show it in green as it's standard
        log_write "[${COL_LIGHT_GREEN}${port_number}${COL_NC}] is in use by ${COL_LIGHT_GREEN}${service_name}${COL_NC}"
      # Otherwise,
      else
        # Show the service name in red since it's non-standard
        log_write "[${COL_LIGHT_RED}${port_number}${COL_NC}] is in use by ${COL_LIGHT_RED}${service_name}${COL_NC} (${COL_CYAN}https://discourse.pi-hole.net/t/hardware-software-requirements/273#ports${COL_NC})"
      fi
}

check_required_ports() {
  echo_current_diagnostic "Ports in use"
  # Since Pi-hole needs 53, 80, and 4711, check what they are being used by
  # so we can detect any issues
  local resolver="dnsmasq"
  local web_server="lighttpd"
  local ftl="pihole-FT"
  # Create an array for these ports in use
  ports_in_use=()
  # Sort the addresses and remove duplicates
  while IFS= read -r line; do
      ports_in_use+=( "$line" )
  done < <( lsof -i -P -n | awk -F' ' '/LISTEN/ {print $9, $1}' | sort -n | uniq | cut -d':' -f2 )

  # Now that we have the values stored,
  for i in ${!ports_in_use[@]}; do
    # loop through them and assign some local variables
    local port_number="$(echo "${ports_in_use[$i]}" | awk '{print $1}')"
    local service_name=$(echo "${ports_in_use[$i]}" | awk '{print $2}')
    # Use a case statement to determine if the right services are using the right ports
    case "${port_number}" in
      53) compare_port_to_service_assigned  "${resolver}"
          ;;
      80) compare_port_to_service_assigned  "${web_server}"
          ;;
      4711) compare_port_to_service_assigned  "${ftl}"
          ;;
      *) log_write "[${port_number}] is in use by ${service_name}";
    esac
  done
}

check_networking() {
  # Runs through several of the functions made earlier; we just clump them
  # together since they are all related to the networking aspect of things
  echo_current_diagnostic "Networking"
  detect_ip_addresses "4"
  detect_ip_addresses "6"
  ping_gateway "4"
  ping_gateway "6"
  check_required_ports
}

check_x_headers() {
  # The X-Headers allow us to determine from the command line if the Web
  # server is operating correctly
  echo_current_diagnostic "Dashboard and block page"
  # Use curl -I to get the header and parse out just the X-Pi-hole one
  local block_page=$(curl -Is localhost | awk '/X-Pi-hole/' | tr -d '\r')
  # Do it for the dashboard as well, as the header is different than above
  local dashboard=$(curl -Is localhost/admin/ | awk '/X-Pi-hole/' | tr -d '\r')
  # Store what the X-Header shoud be in variables for comparision later
  local block_page_working="X-Pi-hole: A black hole for Internet advertisements."
  local dashboard_working="X-Pi-hole: The Pi-hole Web interface is working!"
  # If the X-header found by curl matches what is should be,
  if [[ $block_page == $block_page_working ]]; then
    # display a success message
    log_write "$TICK ${COL_LIGHT_GREEN}${block_page}${COL_NC}"
  else
    # Otherwise, show an error
    log_write "$CROSS ${COL_LIGHT_RED}X-Header does not match or could not be retrieved.${COL_NC}"
  fi

  # Same logic applies to the dashbord as above, if the X-Header matches what a working system shoud have,
  if [[ $dashboard == $dashboard_working ]]; then
    # then we can show a success
    log_write "$TICK ${COL_LIGHT_GREEN}${dashboard}${COL_NC}"
  else
    # Othewise, it's a failure since the X-Headers either don't exist or have been modified in some way
    log_write "$CROSS ${COL_LIGHT_RED}X-Header does not match or could not be retrieved.${COL_NC}"
  fi
}

dig_at() {
  # We need to test if Pi-hole can properly resolve domain names
  # as it is an essential piece of the software

  # Store the arguments as variables with names
  local protocol="${1}"
  local IP="${2}"
  echo_current_diagnostic "Name resolution (IPv${protocol}) using a random blocked domain and a known ad-serving domain"
  # Set more local variables
  local url
  local local_dig
  local pihole_dig
  local remote_dig
  # Use a static domain that we know has IPv4 and IPv6 to avoid false positives
  # Sometimes the randomly chosen domains don't use IPv6, or something else is wrong with them
  local remote_url="doubleclick.com"

  # If the protocol (4 or 6) is 6,
  if [[ ${protocol} == "6" ]]; then
    # Set the IPv6 variables and record type
    local local_address="::1"
    local pihole_address="${IPV6_ADDRESS%/*}"
    local remote_address="2001:4860:4860::8888"
    local record_type="AAAA"
  # Othwerwise, it should be 4
  else
    # so use the IPv4 values
    local local_address="127.0.0.1"
    local pihole_address="${IPV4_ADDRESS%/*}"
    local remote_address="8.8.8.8"
    local record_type="A"
  fi

  # Find a random blocked url that has not been whitelisted.
  # This helps emulate queries to different domains that a user might query
  # It will also give extra assurance that Pi-hole is correctly resolving and blocking domains
  local random_url=$(shuf -n 1 "${PIHOLE_BLOCKLIST_FILE}" | awk -F ' ' '{ print $2 }')

  # First, do a dig on localhost to see if Pi-hole can use itself to block a domain
  if local_dig=$(dig +tries=1 +time=2 -"${protocol}" "${random_url}" @${local_address} +short "${record_type}"); then
    # If it can, show sucess
    log_write "${TICK} ${random_url} ${COL_LIGHT_GREEN}is ${local_dig}${COL_NC} via ${COL_CYAN}localhost$COL_NC (${local_address})"
  else
    # Otherwise, show a failure
    log_write "${CROSS} ${COL_LIGHT_RED}Failed to resolve${COL_NC} ${random_url} via ${COL_LIGHT_RED}localhost${COL_NC} (${local_address})"
  fi

  # Next we need to check if Pi-hole can resolve a domain when the query is sent to it's IP address
  # This better emulates how clients will interact with Pi-hole as opposed to above where Pi-hole is
  # just asing itself locally
  # The default timeouts and tries are reduced in case the DNS server isn't working, so the user isn't waiting for too long

  # If Pi-hole can dig itself from it's IP (not the loopback address)
  if pihole_dig=$(dig +tries=1 +time=2 -"${protocol}" "${random_url}" @${pihole_address} +short "${record_type}"); then
    # show a success
    log_write "${TICK} ${random_url} ${COL_LIGHT_GREEN}is ${pihole_dig}${COL_NC} via ${COL_CYAN}Pi-hole${COL_NC} (${pihole_address})"
  else
    # Othewise, show a failure
    log_write "${CROSS} ${COL_LIGHT_RED}Failed to resolve${COL_NC} ${random_url} via ${COL_LIGHT_RED}Pi-hole${COL_NC} (${pihole_address})"
  fi

  # Finally, we need to make sure legitimate queries can out to the Internet using an external, public DNS server
  # We are using the static remote_url here instead of a random one because we know it works with IPv4 and IPv6
  if remote_dig=$(dig +tries=1 +time=2 -"${protocol}" "${remote_url}" @${remote_address} +short "${record_type}" | head -n1); then
    # If successful, the real IP of the domain will be returned instead of Pi-hole's IP
    log_write "${TICK} ${remote_url} ${COL_LIGHT_GREEN}is ${remote_dig}${COL_NC} via ${COL_CYAN}a remote, public DNS server${COL_NC} (${remote_address})"
  else
    # Otherwise, show an error
    log_write "${CROSS} ${COL_LIGHT_RED}Failed to resolve${COL_NC} ${remote_url} via ${COL_LIGHT_RED}a remote, public DNS server${COL_NC} (${remote_address})"
  fi
}

process_status(){
  # Check to make sure Pi-hole's services are running and active
  echo_current_diagnostic "Pi-hole processes"
  # Store them in an array for easy use
  PROCESSES=( dnsmasq lighttpd pihole-FTL )
  # Local iterator
  local i
  # For each process,
  for i in "${PROCESSES[@]}"; do
    # get its status
    local status_of_process=$(systemctl is-active "${i}")
    # and print it out to the user
    if [[ "${status_of_process}" == "active" ]]; then
      # If it's active, show it in green
      log_write "${TICK} ${COL_LIGHT_GREEN}${i}${COL_NC} daemon is ${COL_LIGHT_GREEN}${status_of_process}${COL_NC}"
    else
      # If it's not, show it in red
      log_write "${CROSS} ${COL_LIGHT_RED}${i}${COL_NC} daemon is ${COL_LIGHT_RED}${status_of_process}${COL_NC}"
    fi
  done
}

make_array_from_file() {
  local filename="${1}"
  local file_content=()
  # If the file is a directory
  if [[ -d "${filename}" ]]; then
    # do nothing since it cannot be parsed
    :
  else
    # Otherwise, read the file line by line
    while IFS= read -r line;do
      # Strip out comments and blank lines
      new_line=$(echo "${line}" | sed -e 's/#.*$//' -e '/^$/d')
      # If the line still has content (a non-zero value)
      if [[ -n "${new_line}" ]]; then
        # Put it into the array
        file_content+=("${new_line}")
      else
        # Otherwise, it's a blank line or comment, so do nothing
        :
      fi
    done < "${filename}"
    for each_line in "${file_content[@]}"; do
      log_write "   ${each_line}"
    done
  fi
}

parse_file() {
  # Set the first argument passed to this function as a named variable for better readability
  local filename="${1}"
  # Put the current Internal Field Separator into another variable so it can be restored later
  OLD_IFS="$IFS"
  # Get the lines that are in the file(s) and store them in an array for parsing later
  IFS=$'\r\n' command eval 'file_info=( $(cat "${filename}") )'

  # Set a named variable for better readability
  local file_lines
  # For each line in the file,
  for file_lines in "${file_info[@]}"; do
    if [[ ! -z "${file_lines}" ]]; then
      # don't include the Web password hash
      [[ "${file_linesline}" =~ ^\#.*$  || ! "${file_lines}" || "${file_lines}" == "WEBPASSWORD="* ]] && continue
      # otherwise, display the lines of the file
      log_write "    ${file_lines}"
    fi
  done
  # Set the IFS back to what it was
  IFS="$OLD_IFS"
}

check_name_resolution() {
  # Check name resoltion from localhost, Pi-hole's IP, and Google's name severs
  # using the function we created earlier
  dig_at 4 "${IPV4_ADDRESS%/*}"
  # If IPv6 enabled,
  if [[ "${IPV6_ADDRESS}" ]]; then
    # check resolution
    dig_at 6 "${IPV6_ADDRESS%/*}"
  fi
}

# This function can check a directory exists
# Pi-hole has files in several places, so we will reuse this function
dir_check() {
  # Set the first argument passed to tihs function as a named variable for better readability
  local directory="${1}"
  # Display the current test that is running
  echo_current_diagnostic "contents of ${COL_CYAN}${directory}${COL_NC}"
  # For each file in the directory,
  for filename in "${directory}"; do
    # check if exists first; if it does,
    if_file_exists "${filename}" && \
    # do nothing
    : || \
    # Otherwise, show an error
    echo_succes_or_fail "${COL_LIGHT_RED}${directory} does not exist.${COL_NC}"
  done
}

list_files_in_dir() {
  # Set the first argument passed to tihs function as a named variable for better readability
  local dir_to_parse="${1}"
  # Store the files found in an array
  local files_found=( $(ls "${dir_to_parse}") )
  # For each file in the array,
  for each_file in "${files_found[@]}"; do
    if [[ -d "${each_file}" ]]; then
      # If it's a directoy, do nothing
      :
    else
      # Then, parse the file's content into an array so each line can be analyzed if need be
      for i in "${!REQUIRED_FILES[@]}"; do
        if [[ "${dir_to_parse}/${each_file}" == ${REQUIRED_FILES[$i]} ]]; then
          # display the filename
          log_write "\n${COL_LIGHT_GREEN}$(ls -ld ${dir_to_parse}/${each_file})${COL_NC}"
          # and parse the file into an array in case we ever need to analyze it line-by-line
          make_array_from_file "${dir_to_parse}/${each_file}"
        else
          :
        fi
      done
    fi
  done
}

show_content_of_files_in_dir() {
  # Set a local variable for better readability
  local directory="${1}"
  # Check if the directory exists
  dir_check "${directory}"
  # if it does, list the files in it
  list_files_in_dir "${directory}"
}

show_content_of_pihole_files() {
  # Show the content of the files in /etc/dnsmasq.d
  show_content_of_files_in_dir "${DNSMASQ_D_DIRECTORY}"
  # Show the content of the files in /etc/lighttpd
  show_content_of_files_in_dir "/etc/lighttpd"
  # Show the content of the files in /etc/lighttpd
  show_content_of_files_in_dir "/etc/cron.d"
  # Show the content of the files in /var/www/html
  # show_content_of_files_in_dir "${WEB_GIT_DIRECTORY}"
}

analyze_gravity_list() {
  echo_current_diagnostic "Gravity list"
  # It's helpful to know how big a user's gravity file is
  gravity_length=$(grep -c ^ "${PIHOLE_BLOCKLIST_FILE}") && \
    log_write "${INFO} ${PIHOLE_BLOCKLIST_FILE} is ${gravity_length} lines long." || \
    # If the previous command failed, something is wrong with the file
    log_write "${CROSS} ${COL_LIGHT_RED}${PIHOLE_BLOCKLIST_FILE} not found!${COL_NC}"
}

tricorder_use_nc_or_ssl() {
  # Users can submit their debug logs using nc (unencrypted) or openssl (enrypted) if available
  # Check for openssl first since encryption is a good thing
  if command -v openssl &> /dev/null; then
    # If the command exists,
    log_write "    * Using ${COL_LIGHT_GREEN}openssl${COL_NC} for transmission."
    # encrypt and transmit the log and store the token returned in a variable
    tricorder_token=$(cat ${PIHOLE_DEBUG_LOG} | openssl s_client -quiet -connect tricorder.pi-hole.net:${TRICORDER_SSL_PORT_NUMBER} 2> /dev/null)
  # Otherwise,
  else
    # use net cat
    log_write "${INFO} Using ${COL_YELLOW}netcat${COL_NC} for transmission."
    tricorder_token=$(cat ${PIHOLE_DEBUG_LOG} | nc tricorder.pi-hole.net ${TRICORDER_NC_PORT_NUMBER})
  fi
}


upload_to_tricorder() {
  # Set the permissions and owner
  chmod 644 ${PIHOLE_DEBUG_LOG}
  chown "$USER":pihole ${PIHOLE_DEBUG_LOG}

  # Let the user know debugging is complete
  log_write ""
  log_write "${COL_LIGHT_PURPLE}********************************************${COL_NC}"
  log_write "${COL_LIGHT_PURPLE}********************************************${COL_NC}"
	log_write "${TICK} ${COL_LIGHT_GREEN}** FINISHED DEBUGGING! **${COL_NC}\n"

  # Provide information on what they should do with their token
	log_write "    * The debug log can be uploaded to tricorder.pi-hole.net for sharing with developers only."
  log_write "    * For more information, see: ${TRICORDER_CONTEST}"
  log_write "    * If available, we'll use openssl to upload the log, otherwise it will fall back to netcat."
  # If pihole -d is running automatically (usually throught the dashboard)
	if [[ "${AUTOMATED}" ]]; then
    # let the user know
    log_write "${INFO} Debug script running in automated mode"
    # and then decide again which tool to use to submit it
    if command -v openssl &> /dev/null; then
      log_write "${INFO} Using ${COL_LIGHT_GREEN}openssl${COL_NC} for transmission."
      tricorder_token=$(openssl s_client -quiet -connect tricorder.pi-hole.net:${TRICORDER_SSL_PORT_NUMBER} 2> /dev/null < /dev/stdin)
    else
      log_write "${INFO} Using ${COL_YELLOW}netcat${COL_NC} for transmission."
      tricorder_token=$(nc tricorder.pi-hole.net ${TRICORDER_NC_PORT_NUMBER} < /dev/stdin)
    fi
	else
    echo ""
    # Give the user a choice of uploading it or not
    # Users can review the log file locally and try to self-diagnose their problem
	  read -r -p "[?] Would you like to upload the log? [y/N] " response
	  case ${response} in
      # If they say yes, run our function for uploading the log
		  [yY][eE][sS]|[yY]) tricorder_use_nc_or_ssl;;
      # If they choose no, just exit out of the script
		  *) log_write "    * Log will ${COL_LIGHT_GREEN}NOT${COL_NC} be uploaded to tricorder.";exit;
	  esac
  fi
	# Check if tricorder.pi-hole.net is reachable and provide token
  # along with some additional useful information
	if [[ -n "${tricorder_token}" ]]; then
    log_write ""
    log_write "${COL_LIGHT_PURPLE}***********************************${COL_NC}"
    log_write "${COL_LIGHT_PURPLE}***********************************${COL_NC}"
		log_write "${TICK} Your debug token is: ${COL_LIGHT_GREEN}${tricorder_token}${COL_NC}"
    log_write "${COL_LIGHT_PURPLE}***********************************${COL_NC}"
    log_write "${COL_LIGHT_PURPLE}***********************************${COL_NC}"
    log_write ""
		log_write "   * Provide the token above to the Pi-hole team for assistance at"
		log_write "   * ${FORUMS_URL}"
    log_write "   * Your log will self-destruct on our server after ${COL_LIGHT_RED}48 hours${COL_NC}."
	else
		log_write "${CROSS}  ${COL_LIGHT_RED}There was an error uploading your debug log.${COL_NC}"
		log_write "   * Please try again or contact the Pi-hole team for assistance."
	fi
		log_write "   * A local copy of the debug log can be found at: ${COL_CYAN}${PIHOLE_DEBUG_LOG}${COL_NC}\n"
}

# Run through all the functions we made
make_temporary_log
# setupVars.conf needs to be sourced before the networking so the values are
# available to the other functions
initiate_debug
source_setup_variables
check_component_versions
check_critical_program_versions
diagnose_operating_system
processor_check
check_networking
check_name_resolution
process_status
parse_setup_vars
check_x_headers
analyze_gravity_list
show_content_of_pihole_files
copy_to_debug_log
upload_to_tricorder
