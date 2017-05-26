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

# These provide the colors we need for making the log more readable
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
  # echo arguments to both the log and the console"
  echo -e "${@}" | tee -a /proc/$$/fd/3
}

copy_to_debug_log() {
  # Copy the contents of file descriptor 3 into the debug log so it can be uploaded to tricorder
  cat /proc/$$/fd/3 >> "${DEBUG_LOG}"
}

echo_succes_or_fail() {
  # Set the first argument passed to this function as a named variable for better readability
  local message="${1}"
  # If the command was successful (a zero),
  if [[ $? -eq 0 ]]; then
    # show success
    log_write "    ${TICK} ${message}"
  else
    # Otherwise, show a error
    log_write "    ${CROSS} ${message}"
  fi
}

initiate_debug() {
  # Clear the screen so the debug log is readable
  clear
  log_write "${COL_LIGHT_PURPLE}*** [ INITIALIZING ]${COL_NC}" 2>&1 | tee "${DEBUG_LOG}"
  # Timestamp the start of the log
  log_write "    ${INFO} $(date "+%Y-%m-%d:%H:%M:%S") debug log has been initiated."
}

# This is a function for visually displaying the curent test that is being run.
# Accepts one variable: the name of what is being diagnosed
# Colors do not show in the dasboard, but the icons do: [i], [✓], and [✗]
echo_current_diagnostic() {
  # Colors are used for visually distinguishing each test in the output
  log_write "\n${COL_LIGHT_PURPLE}*** [ DIAGNOSING ]:${COL_NC} ${1}"
}

file_exists() {
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

check_core_version() {
  # Checks the core version of the Pi-hole codebase
  echo_current_diagnostic "Pi-hole Versions"
  # Store the error message in a variable in case we want to change and/or reuse it
  local error_msg="git status failed"
  # If the pihole git directory exists,
  if_directory_exists "${PIHOLEGITDIR}" && \
    # move into it
    cd "${PIHOLEGITDIR}" || \
    # if not, report an error
    log_write "pihole repo does not exist"
    # If the git status command completes successfully,
    # we can assume we can get the information we want
    if git status &> /dev/null; then
      # The current version the user is on
      PI_HOLE_VERSION=$(git describe --tags --abbrev=0);
      # What branch they are on
      PI_HOLE_BRANCH=$(git rev-parse --abbrev-ref HEAD);
      # The commit they are on
      PI_HOLE_COMMIT=$(git describe --long --dirty --tags --always)
      # echo this information out to the user in a nice format
      # If the current version matches what pihole -v produces, the user is up-to-date
      if [[ "${PI_HOLE_VERSION}" == "$(pihole -v | awk '/Pi-hole/ {print $6}' | cut -d ')' -f1)" ]]; then
        log_write "    ${TICK} Core: ${COL_LIGHT_GREEN}${PI_HOLE_VERSION}${COL_NC}"
      # If not,
      else
        # pring the current version in yellow
        log_write "    ${INFO} Core: ${COL_YELLOW}${PI_HOLE_VERSION:-Untagged}${COL_NC} (See ${COL_CYAN}https://discourse.pi-hole.net/t/how-do-i-update-pi-hole/249${COL_NC} on how to update Pi-hole)"
      fi

      if [[ "${PI_HOLE_BRANCH}" == "master" ]]; then
        log_write "       ${INFO} Branch: ${COL_LIGHT_GREEN}${PI_HOLE_BRANCH}${COL_NC}"
      else
        log_write "       ${INFO} Branch: ${COL_YELLOW}${PI_HOLE_BRANCH:-Detached}${COL_NC} (See ${COL_CYAN}https://discourse.pi-hole.net/t/the-pihole-command-with-examples/738#checkout${COL_NC} for more information)"
      fi
        log_write "       ${INFO} Commit: ${PI_HOLE_COMMIT}"
    # If git status failed,
    else
      # Return an error message
      log_write "${error_msg}"
      # and exit with a non zero code
      return 1
    fi
}

check_web_version() {
  # Local variable for the error message
  local error_msg="git status failed"
  # If the directory exists,
  if_directory_exists "${ADMINGITDIR}" && \
    # move into it
    cd "${ADMINGITDIR}" || \
    # if not, give an error message
    log_write "repo does not exist"
    # If the git status command completes successfully,
    # we can assume we can get the information we want
    if git status &> /dev/null; then
      # The current version the user is on
      WEB_VERSION=$(git describe --tags --abbrev=0);
      # What branch they are on
      WEB_BRANCH=$(git rev-parse --abbrev-ref HEAD);
      # The commit they are on
      WEB_COMMIT=$(git describe --long --dirty --tags --always)
      # echo this information out to the user in a nice format
      if [[ "${WEB_VERSION}" == "$(pihole -v | awk '/AdminLTE/ {print $6}' | cut -d ')' -f1)" ]]; then
        log_write "    ${TICK} Web: ${COL_LIGHT_GREEN}${WEB_VERSION}${COL_NC}"
      else
        log_write "    ${INFO} Web: ${COL_YELLOW}${WEB_VERSION:-Untagged}${COL_NC} (See ${COL_CYAN}https://discourse.pi-hole.net/t/how-do-i-update-pi-hole/249${COL_NC} on how to update Pi-hole)"
      fi

      if [[ "${WEB_BRANCH}" == "master" ]]; then
        log_write "       ${TICK} Branch: ${COL_LIGHT_GREEN}${WEB_BRANCH}${COL_NC}"
      else
        log_write "       ${INFO} Branch: ${COL_YELLOW}${WEB_BRANCH:-Detached}${COL_NC} (See ${COL_CYAN}https://discourse.pi-hole.net/t/the-pihole-command-with-examples/738#checkout${COL_NC} for more information)"
      fi
        log_write "       ${INFO} Commit: ${WEB_COMMIT}"
    # If git status failed,
    else
      # Return an error message
      log_write "${error_msg}"
      # and exit with a non zero code
      return 1
    fi
}

check_ftl_version() {
  # Use the built in command to check FTL's version
  FTL_VERSION=$(pihole-FTL version)
  # and display it to the user
  log_write "    ${INFO} FTL: ${FTL_VERSION}"
}

# Check the current version of the Web server
check_web_server_version() {
  # Store the name in a variable in case we ever want to change it
  WEB_SERVER="lighttpd"
  # Parse out just the version number
  WEB_SERVER_VERSON="$(lighttpd -v |& head -n1 | cut -d '/' -f2 | cut -d ' ' -f1)"
  # Display the information to the user
  log_write "    ${INFO} ${WEB_SERVER}"
  # If the Web server does not have a version (the variable is empty)
  if [[ -z "${WEB_SERVER_VERSON}" ]]; then
    # Display and error
    log_write "       ${CROSS} ${WEB_SERVER} version could not be detected."
  # Otherwise,
  else
    # display the version
    log_write "       ${TICK} ${WEB_SERVER_VERSON}"
  fi
}

# Check the current version of the DNS server
check_resolver_server_version() {
  # Store the name in a variable in case we ever want to change it
  RESOLVER="dnsmasq"
  # Parse out just the version number
  RESOVLER_VERSON="$(dnsmasq -v |& head -n1 | awk '{print $3}')"
  # Display the information to the user
  log_write "    ${INFO} ${RESOLVER}"
  # If the DNS server does not have a version (the variable is empty)
  if [[ -z "${RESOVLER_VERSON}" ]]; then
    # Display and error
    log_write "       ${CROSS} ${RESOLVER} version could not be detected."
  # Otherwise,
  else
    # display the version
    log_write "       ${TICK} ${RESOVLER_VERSON}"
  fi
}

check_php_version() {
  # Parse out just the version number
  PHP_VERSION=$(php -v |& head -n1 | cut -d '-' -f1 | cut -d ' ' -f2)
  # Display the info to the user
  log_write "    ${INFO} PHP"
  # If no version is detected,
  if [[ -z "${PHP_VERSION}" ]]; then
    # show an error
    log_write "       ${CROSS} PHP version could not be detected."
  # otherwise,
  else
    # Show the version
    log_write "       ${TICK} ${PHP_VERSION}"
  fi

}

# These are the most critical dependencies of Pi-hole, so we check for them
# and their versions, using the functions above.
check_critical_dependencies() {
  echo_current_diagnostic "Versions of critical dependencies"
  check_web_server_version
  check_resolver_server_version
  check_php_version
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
    # display the information with the ${INFO} icon
    pretty_name_key=$(echo "${distro_attribute}" | grep "PRETTY_NAME" | cut -d '=' -f1)
    # we need just the OS PRETTY_NAME, so print it when we find it
    if [[ "${pretty_name_key}" == "PRETTY_NAME" ]]; then
      PRETTY_NAME=$(echo "${distro_attribute}" | grep "PRETTY_NAME" | cut -d '=' -f2- | tr -d '"')
      log_write "    ${INFO} ${PRETTY_NAME}"
      # Otherwise, do nothing
    else
      :
    fi
  done
  # Set the IFS back to what it was
  IFS="$OLD_IFS"
}

diagnose_operating_system() {
  # local variable for system requirements
  local faq_url="https://discourse.pi-hole.net/t/hardware-software-requirements/273"
  # error message in a variable so we can easily modify it later (or re-use it)
  local error_msg="Distribution unknown -- most likely you are on an unsupported platform and may run into issues."
  # Display the current test that is running
  echo_current_diagnostic "Operating system"

  # If there is a /etc/*release file, it's probably a supported operating system, so we can
  file_exists /etc/*release && \
    # display the attributes to the user from the function made earlier
    get_distro_attributes || \
    # If it doesn't exist, it's not a system we currently support and link to FAQ
    log_write "    ${CROSS} ${COL_LIGHT_RED}${error_msg}${COL_NC}
         ${INFO} ${COL_LIGHT_RED}Please see${COL_NC}: ${COL_CYAN}${faq_url}${COL_NC}"
}

processor_check() {
  echo_current_diagnostic "Processor"
  # Store the processor type in a variable
  PROCESSOR=$(uname -m)
  # If it does not contain a value,
  if [[ -z "${PROCESSOR}" ]]; then
    # we couldn't detect it, so show an error
    log_write "    ${CROSS} Processor could not be identified."
  # Otherwise,
  else
    # Show the processor type
    log_write "    ${INFO} ${PROCESSOR}"
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
    log_write "    ${TICK} IPv${protocol} on ${PIHOLE_INTERFACE}"
    # Since there may be more than one IP address, store them in an array
    for i in "${!ip_addr_list[@]}"; do
      # For each one in the list, print it out using the iterator as a numbered list
      log_write "       [$i] ${ip_addr_list[$i]}"
    done
  # Othwerwise,
  else
    # explain that the protocol is not configured
    log_write "    ${CROSS} No IPv${protocol} found on ${PIHOLE_INTERFACE}"
    return 1
  fi
}


ping_gateway() {
  # First argument should be a 4 or a 6
  local protocol="${1}"
  # If the protocol is 6,
  if [[ ${protocol} == "6" ]]; then
    # use ping6
    local cmd="ping6"
    # and Google's public IPv6 address
    local public_address="2001:4860:4860::8888"
  # Otherwise,
  else
    # use ping
    local cmd="ping"
    # and Google's public IPv4 address
    local public_address="8.8.8.8"
  fi

  # Find the default gateway using IPv4 or IPv6
  local gateway
  gateway="$(ip -${protocol} route | grep default | cut -d ' ' -f 3)"

  # If the gateway variable has a value (meaning a gateway was found),
  if [[ -n "${gateway}" ]]; then
    # Let the user know we will ping the gateway for a response
    log_write "          ${INFO} Trying three pings on IPv${protocol} gateway at ${gateway}..."
    # Try to quietly ping the gateway 3 times, with a timeout of 3 seconds, using numeric output only,
    # on the pihole interface, and tail the last three lines of the output
    # If pinging the gateway is not successful,
    if ! ping_cmd="$(${cmd} -q -c 3 -W 3 -n ${gateway} -I ${PIHOLE_INTERFACE} | tail -n 3)"; then
      # let the user know
      log_write "          ${CROSS} Gateway did not respond."
      # and return an error code
      return 1
    # Otherwise,
    else
      # show a success
      log_write "          ${TICK} Gateway responded."
      # and return a success code
      return 0
    fi
  fi
}

ping_internet() {
  # Give the first argument a readable name
  local protocol="${1}"
  # If the protocol is 6,
  if [[ ${protocol} == "6" ]]; then
    # use ping6
    local cmd="ping6"
    # and Google's public IPv6 address
    local public_address="2001:4860:4860::8888"
  # Otherwise,
  else
    # use ping
    local cmd="ping"
    # and Google's public IPv4 address
    local public_address="8.8.8.8"
  fi
  echo -n "     ${INFO} Trying three pings on IPv${protocol} to reach the Internet..."
  # Try to ping the address 3 times
  if ! ping_inet="$(${cmd} -q -W 3 -c 3 -n ${public_address} -I ${PIHOLE_INTERFACE} | tail -n 3)"; then
    # if it's unsuccessful, show an error
    log_write "          ${CROSS} Cannot reach the Internet"
    return 1
  # Otherwise,
  else
    # show success
    log_write "          ${TICK} Query responded."
    return 0
  fi
}

check_required_ports() {
  # Since Pi-hole needs 53, 80, and 4711, check what they are being used by
  # so we can detect any issues
  log_write "    ${INFO} Ports in use:"
  # Create an array for these ports in use
  ports_in_use=()
  # Sort the addresses and remove duplicates
  while IFS= read -r line; do
      ports_in_use+=( "$line" )
  done < <( lsof -i -P -n | awk -F' ' '/LISTEN/ {print $9, $1}' | sort -n | uniq | cut -d':' -f2 )

  # Now that we have the values stored,
  for i in ${!ports_in_use[@]}; do
    local port_number="$(echo "${ports_in_use[$i]}" | awk '{print $1}')"
    local service_name=$(echo "${ports_in_use[$i]}" | awk '{print $2}')
    case "${port_number}" in
      53) if [[ "${service_name}" == "dnsmasq" ]]; then
            # if port 53 is dnsmasq, show it in green as it's standard
            log_write "       [${COL_LIGHT_GREEN}${port_number}${COL_NC}] is in use by ${COL_LIGHT_GREEN}${service_name}${COL_NC}"
          # Otherwise,
          else
            # Show the service name in red since it's non-standard
            log_write "       [${COL_LIGHT_RED}${port_number}${COL_NC}] is in use by ${COL_LIGHT_RED}${service_name}${COL_NC}
                Please see: ${COL_CYAN}https://discourse.pi-hole.net/t/hardware-software-requirements/273#ports${COL_NC}"
          fi
          ;;
      80) if [[ "${service_name}" == "lighttpd" ]]; then
            # if port 53 is dnsmasq, show it in green as it's standard
            log_write "       [${COL_LIGHT_GREEN}${port_number}${COL_NC}] is in use by ${COL_LIGHT_GREEN}${service_name}${COL_NC}"
          # Otherwise,
          else
            # Show the service name in red since it's non-standard
            log_write "       [${COL_LIGHT_RED}${port_number}${COL_NC}] is in use by ${COL_LIGHT_RED}${service_name}${COL_NC}
                Please see: ${COL_CYAN}https://discourse.pi-hole.net/t/hardware-software-requirements/273#ports${COL_NC}"
          fi
          ;;
      4711) if [[ "${service_name}" == "pihole-FT" ]]; then
            # if port 4711 is pihole-FTL, show it in green as it's standard
            log_write "       [${COL_LIGHT_GREEN}${port_number}${COL_NC}] is in use by ${COL_LIGHT_GREEN}${service_name}${COL_NC}"
          # Otherwise,
          else
            # Show the service name in yellow since it's non-standard, but should still work
            log_write "       [${COL_YELLOW}${port_number}${COL_NC}] is in use by ${COL_YELLOW}${service_name}${COL_NC}
                Please see: ${COL_CYAN}https://discourse.pi-hole.net/t/hardware-software-requirements/273#ports${COL_NC}"
          fi
          ;;
      *) log_write "       [${port_number}] is in use by ${service_name}";
    esac
  done
}

check_networking() {
  # Runs through several of the functions made earlier; we just clump them
  # together since they are all related to the networking aspect of things
  echo_current_diagnostic "Networking"
  detect_ip_addresses "4"
  ping_gateway "4"
  detect_ip_addresses "6"
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
    log_write "    $TICK ${block_page}"
  # Otherwise,
  else
    # show an error
    log_write "    $CROSS X-Header does not match or could not be retrieved"
  fi

  # Same logic applies to the dashbord as above
  if [[ $dashboard == $dashboard_working ]]; then
    log_write "    $TICK ${dashboard}"
  else
    log_write "    $CROSS X-Header does not match or could not be retrieved"
  fi
}

dig_at() {
  # We need to test if Pi-hole can properly resolve domain names as it is an
  # essential piece of the software that needs to work

  # Store the arguments as variables with names
  local protocol="${1}"
  local IP="${2}"
  echo_current_diagnostic "Domain name resolution (IPv${protocol}) using a random blocked domain"
  # Set more local variables
  local url
  local local_dig
  local pihole_dig
  local remote_dig
  # Use a static domain that we know has IPv4 and IPv6 to avoid false positives
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
  local random_url=$(shuf -n 1 "${GRAVITYFILE}" | awk -F ' ' '{ print $2 }')

  # First do a dig on localhost, to see if Pi-hole can use itself to block a domain
  if local_dig=$(dig -"${protocol}" "${random_url}" @${local_address} +short "${record_type}"); then
    # If it can, show sucess
    log_write "    ${TICK} ${random_url} is ${local_dig} via localhost (${local_address})"
  # Otherwise,
  else
    # show a failure
    log_write "    ${CROSS} Failed to resolve ${random_url} via localhost (${local_address})"
  fi

  # Next we need to check if Pi-hole can resolve a domain when the query is sent to it's IP address
  # This better emulates how clients will interact with Pi-hole as opposed to above where Pi-hole is
  # just asing itself locally
  if pihole_dig=$(dig -"${protocol}" "${random_url}" @${pihole_address} +short "${record_type}"); then
    log_write "    ${TICK} ${random_url} is ${pihole_dig} via Pi-hole (${pihole_address})"
  else
    log_write "    ${CROSS} Failed to resolve ${random_url} via Pi-hole (${pihole_address})"
  fi

  # Finally, we need to make sure legitimate sites can out if using an external, public DNS server
  if remote_dig=$(dig -"${protocol}" "${remote_url}" @${remote_address} +short "${record_type}" | head -n1); then
    # If successful, the real IP of the domain will be returned instead of Pi-hole's IP
    log_write "    ${TICK} ${remote_url} is ${remote_dig} via a remote, public DNS server (${remote_address})"
  else
    log_write "    ${CROSS} Failed to resolve ${remote_url} via a remote, public DNS server (${remote_address})"
  fi
}

process_status(){
  # Check to make sure Pi-hole's services are running and active
  echo_current_diagnostic "Pi-hole processes"
  # Store them in an array for easy use
  PROCESSES=( dnsmasq lighttpd pihole-FTL )
  local i
  # For each process,
  for i in "${PROCESSES[@]}"; do
    # get it's status
    local status_of_process=$(systemctl is-active "${i}")
    # and print it out to the user
    if [[ "${status_of_process}" == "active" ]]; then
      log_write "    ${TICK} ${COL_LIGHT_GREEN}${i}${COL_NC} daemon is ${COL_LIGHT_GREEN}${status_of_process}${COL_NC}"
    else
      log_write "    ${TICK} ${COL_LIGHT_RED}${i}${COL_NC} daemon is ${COL_LIGHT_RED}${status_of_process}${COL_NC}"
    fi
  done
}

parse_file() {
  # Set the first argument passed to tihs function as a named variable for better readability
  local filename="${1}"
  # Put the current Internal Field Separator into another variable so it can be restored later
  OLD_IFS="$IFS"
  # Get the lines that are in the file(s) and store them in an array for parsing later
  IFS=$'\r\n' command eval 'file_info=( $(cat "${filename}") )'

  # Set a named variable for better readability
  local file_lines
  # For each lin in the file,
  for file_lines in "${file_info[@]}"; do
    # display the information with the ${INFO} icon
    log_write "       ${INFO} ${file_lines}"
  done
  # Set the IFS back to what it was
  IFS="$OLD_IFS"
}

diagnose_setup_variables() {
  # Display the current test that is running
  echo_current_diagnostic "Setup variables"

  # If the variable file exists,
  file_exists "${VARSFILE}" && \
    # source it
    source ${VARSFILE};
    log_write "    ${INFO} Sourcing ${VARSFILE}...";
    # and display a green check mark with ${DONE}
    echo_succes_or_fail "${VARSFILE} is readable and has been sourced." || \
    # Othwerwise, error out
    echo_succes_or_fail "${VARSFILE} is not readable.
         ${INFO} $(ls -l ${VARSFILE} 2>/dev/null)";
    parse_file "${VARSFILE}"
}

check_name_resolution() {
  # Check name resoltion from localhost, Pi-hole's IP, and Google's name severs
  # using the function we created earlier
  dig_at 4 "${IPV4_ADDRESS%/*}"
  # If IPv6 enabled, check resolution
  if [[ "${IPV6_ADDRESS}" ]]; then
    dig_at 6 "${IPV6_ADDRESS%/*}"
  fi
}

# This function can check a directory exists
# Pi-hole has files in several places, so we will reuse this function
dir_check() {
  # Set the first argument passed to tihs function as a named variable for better readability
  local directory="${1}"
  # Display the current test that is running
  echo_current_diagnostic "contents of ${directory}"
  # For each file in the directory,
  for filename in "${directory}"; do
    # check if exists first; if it does,
    file_exists "${filename}" && \
    # show a success message
    echo_succes_or_fail "Files detected" || \
    # Otherwise, show an error
    echo_succes_or_fail "directory does not exist"
  done
}

list_files_in_dir() {
  # Set the first argument passed to tihs function as a named variable for better readability
  local dir_to_parse="${1}"
  # Store the files found in an array
  files_found=( $(ls "${dir_to_parse}") )
  # For each file in the arry,
  for each_file in "${files_found[@]}"; do
    # display the information with the ${INFO} icon
    # Also print the permissions and the user/group
    log_write "       ${INFO} $(ls -ld ${dir_to_parse}/${each_file})"
  done

}

check_dnsmasq_d() {
  # Set a local variable for better readability
  local directory=/etc/dnsmasq.d
  # Check if the directory exists
  dir_check "${directory}"
  # if it does, list the files in it
  list_files_in_dir "${directory}"
}

check_lighttpd_d() {
  # Set a local variable for better readability
  local directory=/etc/lighttpd
  # Check if the directory exists
  dir_check "${directory}"
  # if it does, list the files in it
  list_files_in_dir "${directory}"
}

check_cron_d() {
  # Set a local variable for better readability
  local directory=/etc/cron.d
  # Check if the directory exists
  dir_check "${directory}"
  # if it does, list the files in it
  list_files_in_dir "${directory}"
}

check_http_directory() {
  # Set a local variable for better readability
  local directory=/var/www/html
  # Check if the directory exists
  dir_check "${directory}"
  # if it does, list the files in it
  list_files_in_dir "${directory}"
}

analyze_gravity_list() {
  # It's helpful to know how big a user's gravity file is
  gravity_length=$(grep -c ^ "${GRAVITYFILE}") && \
    log_write "   ${INFO} ${GRAVITYFILE} is ${gravity_length} lines long." || \
    # If the previous command failed, something is wrong with the file
    log_write "   ${CROSS} ${GRAVITYFILE} not found!"
}

tricorder_nc_or_ssl() {
  # Users can submit their debug logs using nc (unencrypted) or opensll (enrypted) if available
  # Check fist for openssl since encryption is a good thing
  if command -v openssl &> /dev/null; then
    # If successful
    log_write "   * Using openssl for transmission."
    # transmit the log and store the token returned in the tricorder variable
    tricorder=$(cat /var/log/pihole_debug.log | openssl s_client -quiet -connect tricorder.pi-hole.net:9998 2> /dev/null)
  # Otherwise,
  else
    # use net cat
    log_write "   ${INFO} Using netcat for transmission."
    tricorder=$(cat /var/log/pihole_debug.log | nc tricorder.pi-hole.net 9999)
  fi
}


upload_to_tricorder() {
  # Set the permissions and owner
  chmod 644 ${DEBUG_LOG}
  chown "$USER":pihole ${DEBUG_LOG}

  # Let the user know debugging is complete
  echo ""
	log_write "${TICK} Finished debugging!"

  # Provide information on what they should do with their token
	log_write "   * The debug log can be uploaded to tricorder.pi-hole.net for sharing with developers only."
  log_write "   * For more information, see: https://pi-hole.net/2016/11/07/crack-our-medical-tricorder-win-a-raspberry-pi-3/"
  # If pihole -d is running automatically (usually throught the dashboard)
	if [[ "${AUTOMATED}" ]]; then
    # let the user know
    log_write "   ${INFO} Debug script running in automated mode"
    # and then decide again which tool to use to submit it
    if command -v openssl &> /dev/null; then
      log_write "   ${INFO} Using openssl for transmission."
      openssl s_client -quiet -connect tricorder.pi-hole.net:9998 2> /dev/null < /dev/stdin
    else
      log_write "   ${INFO} Using netcat for transmission."
      nc tricorder.pi-hole.net 9999 < /dev/stdin
    fi
	else
    echo ""
    # Give the user a choice of uploading it or not
    # Users can review the log file locally and try to self-diagnose their problem
	  read -r -p "[?] Would you like to upload the log? [y/N] " response
	  case ${response} in
      # If they say yes, run our function for uploading the log
		  [yY][eE][sS]|[yY]) tricorder_nc_or_ssl;;
      # If they choose no, just exit out of the script
		  *) log_write "   ${INFO} Log will NOT be uploaded to tricorder.";exit;
	  esac
  fi
	# Check if tricorder.pi-hole.net is reachable and provide token
  # along with some additional useful information
	if [[ -n "${tricorder}" ]]; then
    echo ""
    log_write "${COL_LIGHT_PURPLE}***********************************${COL_NC}"
		log_write "${TICK} Your debug token is: ${COL_LIGHT_GREEN}${tricorder}${COL_NC}"
    log_write "${COL_LIGHT_PURPLE}***********************************${COL_NC}"
    log_write ""
		log_write "       Provide this token to the Pi-hole team for assistance:"
    echo ""
		log_write "       https://discourse.pi-hole.net"
	else
		log_write "   ${CROSS}  There was an error uploading your debug log."
		log_write "        Please try again or contact the Pi-hole team for assistance."
	fi
    echo ""
		log_write "       A local copy of the debug log can be found at : /var/log/pihole_debug.log"
    echo ""
}

# Run through all the functions we made
make_temporary_log
initiate_debug
check_core_version
check_web_version
check_ftl_version
# setupVars.conf needs to be sourced before the networking so the values are
# available to the check_networking function
diagnose_setup_variables
diagnose_operating_system
processor_check
check_networking
check_name_resolution
process_status
check_x_headers
check_critical_dependencies
check_dnsmasq_d
check_lighttpd_d
check_http_directory
check_cron_d
copy_to_debug_log
upload_to_tricorder
