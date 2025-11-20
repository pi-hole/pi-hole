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
# shellcheck source=./advanced/Scripts/COL_TABLE
    source ${PIHOLE_COLTABLE_FILE}
else
    COL_NC='\e[0m' # No Color
    COL_RED='\e[1;91m'
    COL_GREEN='\e[1;32m'
    COL_YELLOW='\e[1;33m'
    COL_PURPLE='\e[1;35m'
    COL_CYAN='\e[0;36m'
    TICK="[${COL_GREEN}✓${COL_NC}]"
    CROSS="[${COL_RED}✗${COL_NC}]"
    INFO="[i]"
    #OVER="\r\033[K"
fi

# shellcheck source=/dev/null
. /etc/pihole/versions

# Read the value of an FTL config key. The value is printed to stdout.
get_ftl_conf_value() {
    local key=$1

    # Obtain setting from FTL directly
    pihole-FTL --config "${key}"
}

# FAQ URLs for use in showing the debug log
FAQ_HARDWARE_REQUIREMENTS="${COL_CYAN}https://docs.pi-hole.net/main/prerequisites/${COL_NC}"
FAQ_HARDWARE_REQUIREMENTS_PORTS="${COL_CYAN}https://docs.pi-hole.net/main/prerequisites/#ports${COL_NC}"
FAQ_HARDWARE_REQUIREMENTS_FIREWALLD="${COL_CYAN}https://docs.pi-hole.net/main/prerequisites/#firewalld${COL_NC}"
FAQ_GATEWAY="${COL_CYAN}https://discourse.pi-hole.net/t/why-is-a-default-gateway-important-for-pi-hole/3546${COL_NC}"

# Other URLs we may use
FORUMS_URL="${COL_CYAN}https://discourse.pi-hole.net${COL_NC}"

# Directories required by Pi-hole
# https://discourse.pi-hole.net/t/what-files-does-pi-hole-use/1684
CORE_GIT_DIRECTORY="/etc/.pihole"
CRON_D_DIRECTORY="/etc/cron.d"
DNSMASQ_D_DIRECTORY="/etc/dnsmasq.d"
PIHOLE_DIRECTORY="/etc/pihole"
PIHOLE_SCRIPTS_DIRECTORY="/opt/pihole"
BIN_DIRECTORY="/usr/local/bin"
LOG_DIRECTORY="/var/log/pihole"
HTML_DIRECTORY="$(get_ftl_conf_value "webserver.paths.webroot")"
WEBHOME_PATH="$(get_ftl_conf_value "webserver.paths.webhome")"
WEB_GIT_DIRECTORY="${HTML_DIRECTORY}${WEBHOME_PATH}"
SHM_DIRECTORY="/dev/shm"
ETC="/etc"

# Files required by Pi-hole
# https://discourse.pi-hole.net/t/what-files-does-pi-hole-use/1684
PIHOLE_CRON_FILE="${CRON_D_DIRECTORY}/pihole"

PIHOLE_INSTALL_LOG_FILE="${PIHOLE_DIRECTORY}/install.log"
PIHOLE_RAW_BLOCKLIST_FILES="${PIHOLE_DIRECTORY}/list.*"
PIHOLE_LOGROTATE_FILE="${PIHOLE_DIRECTORY}/logrotate"
PIHOLE_FTL_CONF_FILE="${PIHOLE_DIRECTORY}/pihole.toml"
PIHOLE_DNSMASQ_CONF_FILE="${PIHOLE_DIRECTORY}/dnsmasq.conf"
PIHOLE_VERSIONS_FILE="${PIHOLE_DIRECTORY}/versions"

PIHOLE_GRAVITY_DB_FILE="$(get_ftl_conf_value "files.gravity")"

PIHOLE_FTL_DB_FILE="$(get_ftl_conf_value "files.database")"

PIHOLE_COMMAND="${BIN_DIRECTORY}/pihole"
PIHOLE_COLTABLE_FILE="${BIN_DIRECTORY}/COL_TABLE"

FTL_PID="$(get_ftl_conf_value "files.pid")"

PIHOLE_LOG="${LOG_DIRECTORY}/pihole.log"
PIHOLE_LOG_GZIPS="${LOG_DIRECTORY}/pihole.log.[0-9].*"
PIHOLE_DEBUG_LOG="${LOG_DIRECTORY}/pihole_debug.log"
PIHOLE_FTL_LOG="$(get_ftl_conf_value "files.log.ftl")"
PIHOLE_WEBSERVER_LOG="$(get_ftl_conf_value "files.log.webserver")"

RESOLVCONF="${ETC}/resolv.conf"
DNSMASQ_CONF="${ETC}/dnsmasq.conf"

# Store Pi-hole's processes in an array for easy use and parsing
PIHOLE_PROCESSES=( "pihole-FTL" )

# Store the required directories in an array so it can be parsed through
REQUIRED_FILES=("${PIHOLE_CRON_FILE}"
"${PIHOLE_INSTALL_LOG_FILE}"
"${PIHOLE_RAW_BLOCKLIST_FILES}"
"${PIHOLE_LOCAL_HOSTS_FILE}"
"${PIHOLE_LOGROTATE_FILE}"
"${PIHOLE_FTL_CONF_FILE}"
"${PIHOLE_DNSMASQ_CONF_FILE}"
"${PIHOLE_COMMAND}"
"${PIHOLE_COLTABLE_FILE}"
"${FTL_PID}"
"${PIHOLE_LOG}"
"${PIHOLE_LOG_GZIPS}"
"${PIHOLE_DEBUG_LOG}"
"${PIHOLE_FTL_LOG}"
"${PIHOLE_WEBSERVER_LOG}"
"${RESOLVCONF}"
"${DNSMASQ_CONF}"
"${PIHOLE_VERSIONS_FILE}")

DISCLAIMER="This process collects information from your Pi-hole, and optionally uploads it to a unique and random directory on tricorder.pi-hole.net.

The intent of this script is to allow users to self-diagnose their installations.  This is accomplished by running tests against our software and providing the user with links to FAQ articles when a problem is detected.  Since we are a small team and Pi-hole has been growing steadily, it is our hope that this will help us spend more time on development.

NOTE: All log files auto-delete after 48 hours and ONLY the Pi-hole developers can access your data via the given token. We have taken these extra steps to secure your data and will work to further reduce any personal information gathered.
"

show_disclaimer(){
    log_write "${DISCLAIMER}"
}

make_temporary_log() {
    # Create a random temporary file for the log
    TEMPLOG=$(mktemp /tmp/pihole_temp.XXXXXX)
    # Open handle 3 for templog
    # https://stackoverflow.com/questions/18460186/writing-outputs-to-log-file-and-console
    exec 3>"$TEMPLOG"
    # Delete templog, but allow for addressing via file handle
    # This lets us write to the log without having a temporary file on the drive, which
    # is meant to be a security measure so there is not a lingering file on the drive during the debug process
    rm "$TEMPLOG"
}

log_write() {
    # echo arguments to both the log and the console
    echo -e "${@}" | tee -a /proc/$$/fd/3
}

copy_to_debug_log() {
    # Copy the contents of file descriptor 3 into the debug log
    cat /proc/$$/fd/3 > "${PIHOLE_DEBUG_LOG}"
}

initialize_debug() {
    local system_uptime
    # Clear the screen so the debug log is readable
    clear
    show_disclaimer
    # Display that the debug process is beginning
    log_write "${COL_PURPLE}*** [ INITIALIZING ]${COL_NC}"
    # Timestamp the start of the log
    log_write "${INFO} $(date "+%Y-%m-%d:%H:%M:%S") debug log has been initialized."
    # Uptime of the system
    # credits to https://stackoverflow.com/questions/28353409/bash-format-uptime-to-show-days-hours-minutes
    system_uptime=$(uptime | awk -F'( |,|:)+' '{if ($7=="min") m=$6; else {if ($7~/^day/){if ($9=="min") {d=$6;m=$8} else {d=$6;h=$8;m=$9}} else {h=$6;m=$7}}} {print d+0,"days,",h+0,"hours,",m+0,"minutes"}')
    log_write "${INFO} System has been running for ${system_uptime}"
}

# This is a function for visually displaying the current test that is being run.
# Accepts one variable: the name of what is being diagnosed
echo_current_diagnostic() {
    # Colors are used for visually distinguishing each test in the output
    log_write "\\n${COL_PURPLE}*** [ DIAGNOSING ]:${COL_NC} ${1}"
}

compare_local_version_to_git_version() {
    # The git directory to check
    local git_dir="${1}"
    # The named component of the project (Core or Web)
    local pihole_component="${2}"

    # Display what we are checking
    echo_current_diagnostic "${pihole_component} version"
    # Store the error message in a variable in case we want to change and/or reuse it
    local error_msg="git status failed"
    # If the pihole git directory exists,
    if [[ -d "${git_dir}" ]]; then
        # move into it
        cd "${git_dir}" || \
        # If not, show an error
        log_write "${COL_RED}Could not cd into ${git_dir}$COL_NC"
        if git status &> /dev/null; then
            # The current version the user is on
            local local_version
            local_version=$(git describe --tags --abbrev=0 2> /dev/null);
            # What branch they are on
            local local_branch
            local_branch=$(git rev-parse --abbrev-ref HEAD);
            # The commit they are on
            local local_commit
            local_commit=$(git describe --long --dirty --tags --always)
            # Status of the repo
            local local_status
            local_status=$(git status -s)
            # echo this information out to the user in a nice format
            if [ "${local_version}" ]; then
              log_write "${TICK} Version: ${local_version}"
            elif [ -n "${DOCKER_VERSION}" ]; then
              log_write "${TICK} Version: Pi-hole Docker Container ${COL_BOLD}${DOCKER_VERSION}${COL_NC}"
            else
              log_write "${CROSS} Version: not detected"
            fi

            # Print the repo upstreams
            remotes=$(git remote -v)
            log_write "${INFO} Remotes: ${remotes//$'\n'/'\n             '}"

            # If the repo is on the master branch, they are on the stable codebase
            if [[ "${local_branch}" == "master" ]]; then
                # so the color of the text is green
                log_write "${INFO} Branch: ${COL_GREEN}${local_branch}${COL_NC}"
            # If it is any other branch, they are in a development branch
            else
                # So show that in yellow, signifying it's something to take a look at, but not a critical error
                log_write "${INFO} Branch: ${COL_YELLOW}${local_branch:-Detached}${COL_NC}"
            fi
            # echo the current commit
            log_write "${INFO} Commit: ${local_commit}"
            # if `local_status` is non-null, then the repo is not clean, display details here
            if [[ ${local_status} ]]; then
              # Replace new lines in the status with 12 spaces to make the output cleaner
              log_write "${INFO} Status: ${local_status//$'\n'/'\n            '}"
              local local_diff
              local_diff=$(git diff)
              if [[ ${local_diff} ]]; then
                log_write "${INFO} Diff: ${local_diff//$'\n'/'\n          '}"
              fi
            fi
        # If git status failed,
        else
            # Return an error message
            log_write "${error_msg}"
            # and exit with a non zero code
            return 1
        fi
    else
        # Return an error message
        log_write "${COL_RED}Directory ${git_dir} doesn't exist${COL_NC}"
        # and exit with a non zero code
        return 1
    fi
}

check_ftl_version() {
    local FTL_VERSION FTL_COMMIT FTL_BRANCH
    echo_current_diagnostic "FTL version"
    # Use the built in command to check FTL's version
    FTL_VERSION=$(pihole-FTL version)
    FTL_BRANCH=$(pihole-FTL branch)
    FTL_COMMIT=$(pihole-FTL --hash)


    log_write "${TICK} Version: ${FTL_VERSION}"

    # If they use the master branch, they are on the stable codebase
    if [[ "${FTL_BRANCH}" == "master" ]]; then
        # so the color of the text is green
        log_write "${INFO} Branch: ${COL_GREEN}${FTL_BRANCH}${COL_NC}"
        # If it is any other branch, they are in a development branch
    else
        # So show that in yellow, signifying it's something to take a look at, but not a critical error
        log_write "${INFO} Branch: ${COL_YELLOW}${FTL_BRANCH}${COL_NC}"
    fi

    # echo the current commit
    log_write "${INFO} Commit: ${FTL_COMMIT}"
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

diagnose_operating_system() {
    # error message in a variable so we can easily modify it later (or reuse it)
    local error_msg="Distribution unknown -- most likely you are on an unsupported platform and may run into issues."
    local detected_os
    local detected_version

    # Display the current test that is running
    echo_current_diagnostic "Operating system"

    # If DOCKER_VERSION is set (Sourced from /etc/pihole/versions at start of script), include this information in the debug output
    [ -n "${DOCKER_VERSION}" ] && log_write "${INFO} Pi-hole Docker Container: ${DOCKER_VERSION}"

    # If there is a /etc/*release file, it's probably a supported operating system, so we can
    if ls /etc/*release 1> /dev/null 2>&1; then
        # display the attributes to the user

        detected_os=$(grep "\bID\b" /etc/os-release | cut -d '=' -f2 | tr -d '"')
        detected_version=$(grep VERSION_ID /etc/os-release | cut -d '=' -f2 | tr -d '"')

        log_write "${INFO} Distro: ${detected_os^}"
        log_write "${INFO} Version: ${detected_version}"
    else
        # If it doesn't exist, it's not a system we currently support and link to FAQ
        log_write "${CROSS} ${COL_RED}${error_msg}${COL_NC} (${FAQ_HARDWARE_REQUIREMENTS})"
    fi
}

check_selinux() {
    # SELinux is not supported by the Pi-hole
    echo_current_diagnostic "SELinux"
    # Check if a SELinux configuration file exists
    if [[ -f /etc/selinux/config ]]; then
        # If a SELinux configuration file was found, check the default SELinux mode.
        DEFAULT_SELINUX=$(awk -F= '/^SELINUX=/ {print $2}' /etc/selinux/config)
        case "${DEFAULT_SELINUX,,}" in
            enforcing)
                log_write "${CROSS} ${COL_RED}Default SELinux: $DEFAULT_SELINUX${COL_NC}"
                ;;
            *)  # 'permissive' and 'disabled'
                log_write "${TICK} ${COL_GREEN}Default SELinux: $DEFAULT_SELINUX${COL_NC}";
                ;;
        esac
        # Check the current state of SELinux
        CURRENT_SELINUX=$(getenforce)
        case "${CURRENT_SELINUX,,}" in
            enforcing)
                log_write "${CROSS} ${COL_RED}Current SELinux: $CURRENT_SELINUX${COL_NC}"
                ;;
            *)  # 'permissive' and 'disabled'
                log_write "${TICK} ${COL_GREEN}Current SELinux: $CURRENT_SELINUX${COL_NC}";
                ;;
        esac
    else
        log_write "${INFO} ${COL_GREEN}SELinux not detected${COL_NC}";
    fi
}

check_firewalld() {
    # FirewallD ships by default on Fedora/CentOS/RHEL and enabled upon clean install
    # FirewallD is not configured by the installer and is the responsibility of the user
    echo_current_diagnostic "FirewallD"
    # Check if FirewallD service is enabled
    if command -v systemctl &> /dev/null; then
        # get its status via systemctl
        local firewalld_status
        firewalld_status=$(systemctl is-active firewalld)
        log_write "${INFO} ${COL_GREEN}Firewalld service ${firewalld_status}${COL_NC}";
        if [ "${firewalld_status}" == "active" ]; then
            # test common required service ports
            local firewalld_enabled_services
            firewalld_enabled_services=$(firewall-cmd --list-services)
            local firewalld_expected_services=("http" "https" "dns" "dhcp" "dhcpv6" "ntp")
            for i in "${firewalld_expected_services[@]}"; do
                if [[ "${firewalld_enabled_services}" =~ ${i} ]]; then
                    log_write "${TICK} ${COL_GREEN}  Allow Service: ${i}${COL_NC}";
                else
                    log_write "${CROSS} ${COL_RED}  Allow Service: ${i}${COL_NC} (${FAQ_HARDWARE_REQUIREMENTS_FIREWALLD})"
                fi
            done
            # check for custom FTL FirewallD zone
            local firewalld_zones
            firewalld_zones=$(firewall-cmd --get-zones)
            if [[ "${firewalld_zones}" =~ "ftl" ]]; then
                log_write "${TICK} ${COL_GREEN}FTL Custom Zone Detected${COL_NC}";
                # check FTL custom zone interface: lo
                local firewalld_ftl_zone_interfaces
                firewalld_ftl_zone_interfaces=$(firewall-cmd --zone=ftl --list-interfaces)
                if [[ "${firewalld_ftl_zone_interfaces}" =~ "lo" ]]; then
                    log_write "${TICK} ${COL_GREEN}  Local Interface Detected${COL_NC}";
                else
                    log_write "${CROSS} ${COL_RED}  Local Interface Not Detected${COL_NC} (${FAQ_HARDWARE_REQUIREMENTS_FIREWALLD})"
                fi
            else
                log_write "${CROSS} ${COL_RED}FTL Custom Zone Not Detected${COL_NC} (${FAQ_HARDWARE_REQUIREMENTS_FIREWALLD})"
            fi
        fi
    else
        log_write "${TICK} ${COL_GREEN}Firewalld service not detected${COL_NC}";
    fi
}

run_and_print_command() {
    # Run the command passed as an argument
    local cmd="${1}"
    # Show the command that is being run
    log_write "${INFO} ${cmd}"
    # Run the command and store the output in a variable
    local output
    output=$(${cmd} 2>&1)
    # If the command was successful,
    local return_code
    return_code=$?
    if [[ "${return_code}" -eq 0 ]]; then
        # show the output
        log_write "${output}"
    else
        # otherwise, show an error
        log_write "${CROSS} ${COL_RED}Command failed${COL_NC}"
    fi
}

hardware_check() {
    # Note: the checks are skipped if Pi-hole is running in a docker container

    local skip_msg="${INFO} Not enough permissions inside Docker container ${COL_YELLOW}(skipped)${COL_NC}"

    echo_current_diagnostic "System hardware configuration"
    if [ -n "${DOCKER_VERSION}" ]; then
        log_write "${skip_msg}"
    else
        # Store the output of the command in a variable
        run_and_print_command "lshw -short"
    fi

    echo_current_diagnostic "Processor details"
    if [ -n "${DOCKER_VERSION}" ]; then
        log_write "${skip_msg}"
    else
        # Store the output of the command in a variable
        run_and_print_command "lscpu"
    fi
}

disk_usage() {
    local file_system
    local hide

    echo_current_diagnostic "Disk usage"
    mapfile -t file_system < <(df -h)

    # Some lines of df might contain sensitive information like usernames and passwords.
    # E.g. curlftpfs filesystems (https://www.looklinux.com/mount-ftp-share-on-linux-using-curlftps/)
    # We are not interested in those lines so we collect keyword, to remove them from the output
    # Additional keywords can be added, separated by "|"
    hide="curlftpfs"

    # only show those lines not containing a sensitive phrase
    for line in "${file_system[@]}"; do
      if [[ ! $line =~ $hide ]]; then
        log_write "   ${line}"
      fi
    done
}

parse_locale() {
    local pihole_locale
    echo_current_diagnostic "Locale"
    pihole_locale="$(locale)"
    parse_file "${pihole_locale}"
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
    # Find the default gateways using IPv4 or IPv6
    local gateway gateway_addr gateway_iface default_route

    log_write "${INFO} Default IPv${protocol} gateway(s):"

    while IFS= read -r default_route; do
        gateway_addr=$(jq -r '.gateway' <<< "${default_route}")
        gateway_iface=$(jq -r '.dev' <<< "${default_route}")
        log_write "     ${gateway_addr}%${gateway_iface}"
    done < <(ip -j -"${protocol}" route | jq -c '.[] | select(.dst == "default")')

    # Find the first default route
    default_route=$(ip -j -"${protocol}" route show default)
    if echo "$default_route" | grep 'gateway' | grep -q 'dev'; then
        gateway_addr=$(echo "$default_route" | jq -r -c '.[0].gateway')
        gateway_iface=$(echo "$default_route" | jq -r -c '.[0].dev')
    else
        log_write "     Unable to determine gateway address for IPv${protocol}"
    fi

    # If there was at least one gateway
    if [ -n "${gateway_addr}" ]; then
        # Append the interface to the gateway address if it is a link-local address
        if [[ "${gateway_addr}" =~ ^fe80 ]]; then
            gateway="${gateway_addr}%${gateway_iface}"
        else
            gateway="${gateway_addr}"
        fi
        # Let the user know we will ping the gateway for a response
        log_write "   * Pinging first gateway ${gateway}..."
        # Try to quietly ping the gateway 3 times, with a timeout of 3 seconds, using numeric output only,
        # on the pihole interface, and tail the last three lines of the output
        # If pinging the gateway is not successful,
        if ! ${cmd} -c 1 -W 2 -n "${gateway}" >/dev/null; then
            # let the user know
            log_write "${CROSS} ${COL_RED}Gateway did not respond.${COL_NC} ($FAQ_GATEWAY)\\n"
            # and return an error code
            return 1
        # Otherwise,
        else
            # show a success
            log_write "${TICK} ${COL_GREEN}Gateway responded.${COL_NC}"
            # and return a success code
            return 0
        fi
    fi
}

ping_internet() {
    local protocol="${1}"
    # Ping a public address using the protocol passed as an argument
    ping_ipv4_or_ipv6 "${protocol}"
    log_write "* Checking Internet connectivity via IPv${protocol}..."
    # Try to ping the address 3 times
    if ! ${cmd} -c 1 -W 2 -n ${public_address} -I "${PIHOLE_INTERFACE}" >/dev/null; then
        # if it's unsuccessful, show an error
        log_write "${CROSS} ${COL_RED}Cannot reach the Internet.${COL_NC}\\n"
        return 1
    else
        # Otherwise, show success
        log_write "${TICK} ${COL_GREEN}Query responded.${COL_NC}\\n"
        return 0
    fi
}

compare_port_to_service_assigned() {
    local service_name
    local expected_service
    local port

    service_name="${2}"
    expected_service="${1}"
    port="${3}"

    # If the service is a Pi-hole service, highlight it in green
    if [[ "${service_name}" == "${expected_service}" ]]; then
        log_write "${TICK} ${COL_GREEN}${port}${COL_NC} is in use by ${COL_GREEN}${service_name}${COL_NC}"
    # Otherwise,
    else
        # Show the service name in red since it's non-standard
        log_write "${CROSS} ${COL_RED}${port}${COL_NC} is in use by ${COL_RED}${service_name}${COL_NC} (${FAQ_HARDWARE_REQUIREMENTS_PORTS})"
    fi
}

check_required_ports() {
    echo_current_diagnostic "Ports in use"
    # Since Pi-hole needs various ports, check what they are being used by
    # so we can detect any issues
    local ftl="pihole-FTL"
    # Create an array for these ports in use
    ports_in_use=()
    # Sort the addresses and remove duplicates
    while IFS= read -r line; do
        ports_in_use+=( "$line" )
    done < <( ss --listening --numeric --tcp --udp --processes --no-header )

    local ports_configured
    # Get all configured ports
    ports_configured="$(pihole-FTL --config "webserver.port")"
    # Remove all non-didgits, split into an array at ","
    ports_configured="${ports_configured//[!0-9,]/}"
    mapfile -d "," -t ports_configured < <(echo "${ports_configured}")
    # Add port 53
    ports_configured+=("53")

    local protocol_type port_number service_name
    # Now that we have the values stored,
    for i in "${!ports_in_use[@]}"; do
        # loop through them and assign some local variables
        read -r protocol_type port_number service_name <<< "$(
            awk '{
                p=$1; n=$5; s=$7
                gsub(/users:\(\("/,"",s)
                gsub(/".*/,"",s)
                print p, n, s
            }' <<< "${ports_in_use[$i]}"
        )"

        # Check if the right services are using the right ports
        if [[ ${ports_configured[*]} =~ ${port_number##*:} ]]; then
            compare_port_to_service_assigned  "${ftl}" "${service_name}" "${protocol_type}:${port_number}"
        else
            # If it's not a default port that Pi-hole needs, just print it out for the user to see
            log_write "    ${protocol_type}:${port_number} is in use by ${service_name:=<unknown>}";
        fi
    done
}

ip_command() {
    # Obtain and log information from "ip XYZ show" commands
    echo_current_diagnostic "${2}"
    local entries=()
    mapfile -t entries < <(ip "${1}" show)
    for line in "${entries[@]}"; do
        log_write "   ${line}"
    done
}

check_ip_command() {
    ip_command "addr" "Network interfaces and addresses"
    ip_command "route" "Network routing table"
}

check_networking() {
    # Runs through several of the functions made earlier; we just clump them
    # together since they are all related to the networking aspect of things
    echo_current_diagnostic "Networking"
    ping_gateway "4"
    ping_gateway "6"
    # Skip the following check if installed in docker container. Unpriv'ed containers do not have access to the information required
    # to resolve the service name listening - and the container should not start if there was a port conflict anyway
    [ -z "${DOCKER_VERSION}" ] && check_required_ports
}

dig_at() {
    # We need to test if Pi-hole can properly resolve domain names
    # as it is an essential piece of the software

    # Store the arguments as variables with names
    local protocol="${1}"
    echo_current_diagnostic "Name resolution (IPv${protocol}) using a random blocked domain and a known ad-serving domain"
    # Set more local variables
    # We need to test name resolution locally, via Pi-hole, and via a public resolver
    local local_dig
    local remote_dig
    local interfaces
    local addresses
    # Use a static domain that we know has IPv4 and IPv6 to avoid false positives
    # Sometimes the randomly chosen domains don't use IPv6, or something else is wrong with them
    local remote_url="doubleclick.com"

    # If the protocol (4 or 6) is 6,
    if [[ ${protocol} == "6" ]]; then
        # Set the IPv6 variables and record type
        local local_address="::1"
        local remote_address="2001:4860:4860::8888"
        local sed_selector="inet6"
        local record_type="AAAA"
    # Otherwise, it should be 4
    else
        # so use the IPv4 values
        local local_address="127.0.0.1"
        local remote_address="8.8.8.8"
        local sed_selector="inet"
        local record_type="A"
    fi

    # Find a random blocked url that has not been allowlisted and is not ABP style.
    # This helps emulate queries to different domains that a user might query
    # It will also give extra assurance that Pi-hole is correctly resolving and blocking domains
    local random_url
    random_url=$(pihole-FTL sqlite3 -ni "${PIHOLE_GRAVITY_DB_FILE}" "SELECT domain FROM vw_gravity WHERE domain not like '||%^' ORDER BY RANDOM() LIMIT 1")
    # Fallback if no non-ABP style domains were found
    if [ -z "${random_url}" ]; then
        random_url="flurry.com"
    fi

    # Next we need to check if Pi-hole can resolve a domain when the query is sent to it's IP address
    # This better emulates how clients will interact with Pi-hole as opposed to above where Pi-hole is
    # just asing itself locally
    # The default timeouts and tries are reduced in case the DNS server isn't working, so the user isn't
    # waiting for too long
    #
    # Turn off history expansion such that the "!" in the sed command cannot do silly things
    set +H
    # Get interfaces
    # sed logic breakdown:
    #     / master /d;
    #          Removes all interfaces that are slaves of others (e.g. virtual docker interfaces)
    #     /UP/!d;
    #          Removes all interfaces which are not UP
    #     s/^[0-9]*: //g;
    #          Removes interface index
    #     s/@.*//g;
    #          Removes everything after @ (if found)
    #     s/: <.*//g;
    #          Removes everything after the interface name
    interfaces="$(ip link show | sed "/ master /d;/UP/!d;s/^[0-9]*: //g;s/@.*//g;s/: <.*//g;")"

    while IFS= read -r iface ; do
        # Get addresses of current interface
        # sed logic breakdown:
        #     /inet(|6) /!d;
        #          Removes all lines from ip a that do not contain either "inet " or "inet6 "
        #     s/^.*inet(|6) //g;
        #          Removes all leading whitespace as well as the "inet " or "inet6 " string
        #     s/\/.*$//g;
        #          Removes CIDR and everything thereafter (e.g., scope properties)
        addresses="$(ip address show dev "${iface}" | sed "/${sed_selector} /!d;s/^.*${sed_selector} //g;s/\/.*$//g;")"
        if [ -n "${addresses}" ]; then
            while IFS= read -r local_address ; do
                # If ${local_address} is an IPv6 link-local address, append the interface name to it
                if [[ "${local_address}" =~ ^fe80 ]]; then
                    local_address="${local_address}%${iface}"
                fi

              # Check if Pi-hole can use itself to block a domain
                if local_dig="$(dig +tries=1 +time=2 -"${protocol}" "${random_url}" @"${local_address}" "${record_type}" -p "$(get_ftl_conf_value "dns.port")")"; then
                    # If it can, show success
                    if [[ "${local_dig}" == *"status: NOERROR"* ]]; then
                        local_dig="NOERROR"
                    elif [[ "${local_dig}" == *"status: NXDOMAIN"* ]]; then
                        local_dig="NXDOMAIN"
                    else
                        # Extract the first entry in the answer section from dig's output,
                        # replacing any multiple spaces and tabs with a single space
                        local_dig="$(echo "${local_dig}" | grep -A1 "ANSWER SECTION" | grep -v "ANSWER SECTION" | tr -s " \t" " ")"
                    fi
                    log_write "${TICK} ${random_url} ${COL_GREEN}is ${local_dig}${COL_NC} on ${COL_CYAN}${iface}${COL_NC} (${COL_CYAN}${local_address}${COL_NC})"
                else
                    # Otherwise, show a failure
                    log_write "${CROSS} ${COL_RED}Failed to resolve${COL_NC} ${random_url} on ${COL_RED}${iface}${COL_NC} (${COL_RED}${local_address}${COL_NC})"
                fi
          done <<< "${addresses}"
        else
          log_write "${TICK} No IPv${protocol} address available on ${COL_CYAN}${iface}${COL_NC}"
        fi
    done <<< "${interfaces}"

    # Finally, we need to make sure legitimate queries can out to the Internet using an external, public DNS server
    # We are using the static remote_url here instead of a random one because we know it works with IPv4 and IPv6
    if remote_dig=$(dig +tries=1 +time=2 -"${protocol}" "${remote_url}" @"${remote_address}" +short "${record_type}" | head -n1); then
        # If successful, the real IP of the domain will be returned instead of Pi-hole's IP
        log_write "${TICK} ${remote_url} ${COL_GREEN}is ${remote_dig}${COL_NC} via ${COL_CYAN}a remote, public DNS server${COL_NC} (${remote_address})"
    else
        # Otherwise, show an error
        log_write "${CROSS} ${COL_RED}Failed to resolve${COL_NC} ${remote_url} via ${COL_RED}a remote, public DNS server${COL_NC} (${remote_address})"
    fi
}

process_status(){
    # Check to make sure Pi-hole's services are running and active
    echo_current_diagnostic "Pi-hole processes"

    # Local iterator
    local i

    # For each process,
    for i in "${PIHOLE_PROCESSES[@]}"; do
        local status_of_process

        # If systemd
        if command -v systemctl &> /dev/null; then
            # get its status via systemctl
            status_of_process=$(systemctl is-active "${i}")
        else
            # Otherwise, use the service command and mock the output of `systemctl is-active`

            # If it is a docker container, there is no systemctl or service. Do nothing.
            if [ -n "${DOCKER_VERSION}" ]; then
                :
            else
            # non-Docker system
                if service "${i}" status | grep -q -E 'is\srunning|started'; then
                    status_of_process="active"
                else
                    status_of_process="inactive"
                fi
            fi
        fi

        # and print it out to the user
        if [ -n "${DOCKER_VERSION}" ]; then
            # If it's a Docker container, the test was skipped
            log_write "${INFO} systemctl/service not installed inside docker container ${COL_YELLOW}(skipped)${COL_NC}"
        elif [[ "${status_of_process}" == "active" ]]; then
            # If it's active, show it in green
            log_write "${TICK} ${COL_GREEN}${i}${COL_NC} daemon is ${COL_GREEN}${status_of_process}${COL_NC}"
        else
            # If it's not, show it in red
            log_write "${CROSS} ${COL_RED}${i}${COL_NC} daemon is ${COL_RED}${status_of_process}${COL_NC}"
        fi
    done
}

ftl_full_status(){
    # if using systemd print the full status of pihole-FTL
    echo_current_diagnostic "Pi-hole-FTL full status"
    local FTL_status
    if command -v systemctl &> /dev/null; then
      FTL_status=$(systemctl status --full --no-pager pihole-FTL.service)
      log_write "   ${FTL_status}"
    elif [ -n "${DOCKER_VERSION}" ]; then
      log_write "${INFO} systemctl/service not installed inside docker container ${COL_YELLOW}(skipped)${COL_NC}"
    else
      log_write "${INFO} systemctl:  command not found"
    fi
}

make_array_from_file() {
    local filename="${1}"

    # If the file is a directory do nothing since it cannot be parsed
    [[ -d "${filename}" ]] && return

    # The second argument can put a limit on how many line should be read from the file
    # Since some of the files are so large, this is helpful to limit the output
    local limit=${2}
    # A local iterator for testing if we are at the limit above
    local i=0

    # Process the file, strip out comments and blank lines
    local processed
    processed=$(sed -e 's/^\s*#.*$//' -e '/^$/d' "${filename}")

    while IFS= read -r line; do
        # If the string contains "### CHANGED", highlight this part in red
        log_write "   ${line//### CHANGED/${COL_RED}### CHANGED${COL_NC}}"
        ((i++))
        # if the limit of lines we want to see is exceeded do nothing
        [[ -n ${limit} && $i -eq ${limit} ]] && break
    done <<< "$processed"
}

parse_file() {
    # Set the first argument passed to this function as a named variable for better readability
    local filename="${1}"
    # Put the current Internal Field Separator into another variable so it can be restored later
    OLD_IFS="$IFS"
    # Get the lines that are in the file(s) and store them in an array for parsing later
    local file_info
    if [[ -f "$filename" ]]; then
        IFS=$'\r\n' command eval 'file_info=( $(cat "${filename}") )'
    else
        read -r -a file_info <<< "$filename"
    fi
    # Set a named variable for better readability
    local file_lines
    # For each line in the file,
    for file_lines in "${file_info[@]}"; do
        if [[ -n "${file_lines}" ]]; then
            # skip empty and comment lines line
            [[ "${file_lines}" =~ ^[[:space:]]*\#.*$  || ! "${file_lines}" ]] && continue
            # remove the password hash from the output (*"pwhash = "*)
            [[ "${file_lines}" == *"pwhash ="* ]] && file_lines=$(echo "${file_lines}" | sed -e 's/\(pwhash = \).*/\1<removed>/')
            # otherwise, display the lines of the file
            log_write "    ${file_lines}"
        fi
    done
    # Set the IFS back to what it was
    IFS="$OLD_IFS"
}

check_name_resolution() {
    # Check name resolution from localhost, Pi-hole's IP, and Google's name servers
    # using the function we created earlier
    dig_at 4
    dig_at 6
}

# This function can check a directory exists
# Pi-hole has files in several places, so we will reuse this function
dir_check() {
    # Set the first argument passed to this function as a named variable for better readability
    local directory="${1}"
    # Display the current test that is running
    echo_current_diagnostic "contents of ${COL_CYAN}${directory}${COL_NC}"
    # For each file in the directory,
    for filename in ${directory}; do
        # check if exists first; if it does,
        if ls "${filename}" 1> /dev/null 2>&1; then
            # do nothing
            true
            return
        else
            # Otherwise, show an error
            log_write "${COL_RED}${directory} does not exist.${COL_NC}"
            false
            return
        fi
    done
}

list_files_in_dir() {
    # Set the first argument passed to this function as a named variable for better readability
    local dir_to_parse="${1}"

    # show files and sizes of some directories, don't print the file content (yet)
    if [[ "${dir_to_parse}" == "${SHM_DIRECTORY}" ]]; then
        # SHM file - we do not want to see the content, but we want to see the files and their sizes
        log_write "$(ls -lh "${dir_to_parse}/")"
    fi

    # Store the files found in an array
    local files_found=("${dir_to_parse}"/*)
    # For each file in the array,
    for each_file in "${files_found[@]}"; do
        if [[ -d "${each_file}" ]]; then
            # If it's a directory, do nothing
            :
        elif [[ "${each_file}" == "${PIHOLE_DEBUG_LOG}" ]] || \
            [[ "${each_file}" == "${PIHOLE_RAW_BLOCKLIST_FILES}" ]] || \
            [[ "${each_file}" == "${PIHOLE_INSTALL_LOG_FILE}" ]] || \
            [[ "${each_file}" == "${PIHOLE_LOG}" ]] || \
            [[ "${each_file}" == "${PIHOLE_LOG_GZIPS}" ]]; then
            :
        elif [[ "${dir_to_parse}" == "${DNSMASQ_D_DIRECTORY}" ]]; then
            # in case of the dnsmasq directory include all files in the debug output
            log_write "\\n${COL_GREEN}$(ls -lhd "${each_file}")${COL_NC}"
            make_array_from_file "${each_file}"
        else
            # Then, parse the file's content into an array so each line can be analyzed if need be
            for i in "${!REQUIRED_FILES[@]}"; do
                if [[ "${each_file}" == "${REQUIRED_FILES[$i]}" ]]; then
                    # display the filename
                    log_write "\\n${COL_GREEN}$(ls -lhd "${each_file}")${COL_NC}"
                    # Check if the file we want to view has a limit (because sometimes we just need a little bit of info from the file, not the entire thing)
                    case "${each_file}" in
                        # If it's Web server log, give the first and last 25 lines
                        "${PIHOLE_WEBSERVER_LOG}") head_tail_log "${each_file}" 25
                            ;;
                        # Same for the FTL log
                        "${PIHOLE_FTL_LOG}") head_tail_log "${each_file}" 35
                            ;;
                        # parse the file into an array in case we ever need to analyze it line-by-line
                        *) make_array_from_file "${each_file}";
                    esac
                else
                    # Otherwise, do nothing since it's not a file needed for Pi-hole so we don't care about it
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
    if dir_check "${directory}"; then
        # if it does, list the files in it
        list_files_in_dir "${directory}"
    fi
}

show_content_of_pihole_files() {
    # Show the content of the files in each of Pi-hole's folders
    show_content_of_files_in_dir "${PIHOLE_DIRECTORY}"
    show_content_of_files_in_dir "${DNSMASQ_D_DIRECTORY}"
    show_content_of_files_in_dir "${CRON_D_DIRECTORY}"
    show_content_of_files_in_dir "${LOG_DIRECTORY}"
    show_content_of_files_in_dir "${SHM_DIRECTORY}"
    show_content_of_files_in_dir "${ETC}"
}

head_tail_log() {
    # The file being processed
    local filename="${1}"
    # The number of lines to use for head and tail
    local qty="${2}"
    local filebasename="${filename##*/}"
    local head_line
    local tail_line
    # Put the current Internal Field Separator into another variable so it can be restored later
    OLD_IFS="$IFS"
    # Get the lines that are in the file(s) and store them in an array for parsing later
    IFS=$'\r\n'
    local log_head=()
    mapfile -t log_head < <(head -n "${qty}" "${filename}")
    log_write "   ${COL_CYAN}-----head of ${filebasename}------${COL_NC}"
    for head_line in "${log_head[@]}"; do
        log_write "   ${head_line}"
    done
    log_write ""
    local log_tail=()
    mapfile -t log_tail < <(tail -n "${qty}" "${filename}")
    log_write "   ${COL_CYAN}-----tail of ${filebasename}------${COL_NC}"
    for tail_line in "${log_tail[@]}"; do
        log_write "   ${tail_line}"
    done
    # Set the IFS back to what it was
    IFS="$OLD_IFS"
}

show_db_entries() {
    local title="${1}"
    local query="${2}"
    local widths="${3}"

    echo_current_diagnostic "${title}"

    OLD_IFS="$IFS"
    IFS=$'\r\n'
    local entries=()
    mapfile -t entries < <(\
        pihole-FTL sqlite3 -ni "${PIHOLE_GRAVITY_DB_FILE}" \
            -cmd ".headers on" \
            -cmd ".mode column" \
            -cmd ".width ${widths}" \
            "${query}"\
    )

    for line in "${entries[@]}"; do
        log_write "   ${line}"
    done

    IFS="$OLD_IFS"
}

show_FTL_db_entries() {
    local title="${1}"
    local query="${2}"
    local widths="${3}"

    echo_current_diagnostic "${title}"

    OLD_IFS="$IFS"
    IFS=$'\r\n'
    local entries=()
    mapfile -t entries < <(\
        pihole-FTL sqlite3 -ni "${PIHOLE_FTL_DB_FILE}" \
            -cmd ".headers on" \
            -cmd ".mode column" \
            -cmd ".width ${widths}" \
            "${query}"\
    )

    for line in "${entries[@]}"; do
        log_write "   ${line}"
    done

    IFS="$OLD_IFS"
}

check_dhcp_servers() {
    echo_current_diagnostic "Discovering active DHCP servers (takes 6 seconds)"

    OLD_IFS="$IFS"
    IFS=$'\n'
    local entries=()
    mapfile -t entries < <(pihole-FTL dhcp-discover & spinner)

    for line in "${entries[@]}"; do
        log_write "   ${line}"
    done

    IFS="$OLD_IFS"
}

show_groups() {
    show_db_entries "Groups" "SELECT id,CASE enabled WHEN '0' THEN '  no' WHEN '1' THEN '  yes' ELSE enabled END enabled,name,datetime(date_added,'unixepoch','localtime') date_added,datetime(date_modified,'unixepoch','localtime') date_modified,description FROM \"group\"" "4 7 50 19 19 50"
}

show_adlists() {
    show_db_entries "Adlists" "SELECT id,CASE enabled WHEN '0' THEN '  no' WHEN '1' THEN '  yes' ELSE enabled END enabled,GROUP_CONCAT(adlist_by_group.group_id) group_ids, CASE type WHEN '0' THEN 'Block' WHEN '1' THEN 'Allow' ELSE type END type, address,datetime(date_added,'unixepoch','localtime') date_added,datetime(date_modified,'unixepoch','localtime') date_modified,comment FROM adlist LEFT JOIN adlist_by_group ON adlist.id = adlist_by_group.adlist_id GROUP BY id;" "5 7 12 5 100 19 19 50"
}

show_domainlist() {
    show_db_entries "Domainlist" "SELECT id,CASE type WHEN '0' THEN 'exact-allow' WHEN '1' THEN 'exact-deny' WHEN '2' THEN 'regex-allow' WHEN '3' THEN 'regex-deny' ELSE type END type,CASE enabled WHEN '0' THEN '  no' WHEN '1' THEN '  yes' ELSE enabled END enabled,GROUP_CONCAT(domainlist_by_group.group_id) group_ids,domain,datetime(date_added,'unixepoch','localtime') date_added,datetime(date_modified,'unixepoch','localtime') date_modified,comment FROM domainlist LEFT JOIN domainlist_by_group ON domainlist.id = domainlist_by_group.domainlist_id GROUP BY id;" "5 11 7 12 100 19 19 50"
}

show_clients() {
    show_db_entries "Clients" "SELECT id,GROUP_CONCAT(client_by_group.group_id) group_ids,ip,datetime(date_added,'unixepoch','localtime') date_added,datetime(date_modified,'unixepoch','localtime') date_modified,comment FROM client LEFT JOIN client_by_group ON client.id = client_by_group.client_id GROUP BY id;" "4 12 100 19 19 50"
}

show_messages() {
    show_FTL_db_entries "Pi-hole diagnosis messages" "SELECT count (message) as count, datetime(max(timestamp),'unixepoch','localtime') as 'last timestamp', type, message, blob1, blob2, blob3, blob4, blob5 FROM message GROUP BY type, message, blob1, blob2, blob3, blob4, blob5;" "6 19 20 60 20 20 20 20 20"
}

database_permissions() {
    local permissions
    permissions=$(ls -lhd "${1}")
    log_write "${COL_GREEN}${permissions}${COL_NC}"
}

analyze_gravity_list() {
    echo_current_diagnostic "Gravity Database"

    database_permissions "${PIHOLE_GRAVITY_DB_FILE}"

    # if users want to check database integrity
    if [[ "${CHECK_DATABASE}" = true ]]; then
        database_integrity_check "${PIHOLE_GRAVITY_DB_FILE}"
    fi

    show_db_entries "Info table" "SELECT property,value FROM info" "20 40"
    gravity_updated_raw="$(pihole-FTL sqlite3 -ni "${PIHOLE_GRAVITY_DB_FILE}" "SELECT value FROM info where property = 'updated'")"
    gravity_updated="$(date -d @"${gravity_updated_raw}")"
    log_write "   Last gravity run finished at: ${COL_CYAN}${gravity_updated}${COL_NC}"
    log_write ""

    OLD_IFS="$IFS"
    IFS=$'\r\n'
    local gravity_sample=()
    mapfile -t gravity_sample < <(pihole-FTL sqlite3 -ni "${PIHOLE_GRAVITY_DB_FILE}" "SELECT domain FROM vw_gravity LIMIT 10")
    log_write "   ${COL_CYAN}----- First 10 Gravity Domains -----${COL_NC}"

    for line in "${gravity_sample[@]}"; do
        log_write "   ${line}"
    done

    log_write ""
    IFS="$OLD_IFS"
}

analyze_ftl_db() {
    echo_current_diagnostic "Pi-hole FTL Query Database"
    database_permissions "${PIHOLE_FTL_DB_FILE}"
    # if users want to check database integrity
    if [[ "${CHECK_DATABASE}" = true ]]; then
        database_integrity_check "${PIHOLE_FTL_DB_FILE}"
    fi
}

database_integrity_check(){
    local result
    local database="${1}"

    log_write "${INFO} Checking integrity of ${database} ... (this can take several minutes)"
    result="$(pihole-FTL sqlite3 -ni "${database}" "PRAGMA integrity_check" 2>&1 & spinner)"
    if [[ ${result} = "ok" ]]; then
      log_write "${TICK} Integrity of ${database} intact"


      log_write "${INFO} Checking foreign key constraints of ${database} ... (this can take several minutes)"
      unset result
      result="$(pihole-FTL sqlite3 -ni "${database}" -cmd ".headers on" -cmd ".mode column" "PRAGMA foreign_key_check" 2>&1 & spinner)"
      if [[ -z ${result} ]]; then
        log_write "${TICK} No foreign key errors in ${database}"
      else
        log_write "${CROSS} ${COL_RED}Foreign key errors in ${database} found.${COL_NC}"
        while IFS= read -r line ; do
            log_write "    $line"
        done <<< "$result"
      fi

    else
      log_write "${CROSS} ${COL_RED}Integrity errors in ${database} found.\n${COL_NC}"
      while IFS= read -r line ; do
        log_write "    $line"
      done <<< "$result"
    fi

}

# Show a text spinner during a long process run
spinner(){
    # Show the spinner only if there is a tty
    if tty -s; then
        # PID of the most recent background process
        _PID=$!
        _spin="/-\|"
        _start=0
        _elapsed=0
        _i=1

        # Start the counter
        _start=$(date +%s)

        # Hide the cursor
        tput civis > /dev/tty

        # ensures cursor is visible again, in case of premature exit
        trap 'tput cnorm > /dev/tty' EXIT

        while [ -d /proc/$_PID ]; do
            _elapsed=$(( $(date +%s) - _start ))
            # use hours only if needed
            if [ "$_elapsed" -lt 3600 ]; then
                printf "\r${_spin:_i++%${#_spin}:1} %02d:%02d" $((_elapsed/60)) $((_elapsed%60)) >"$(tty)"
            else
                printf "\r${_spin:_i++%${#_spin}:1} %02d:%02d:%02d" $((_elapsed/3600)) $(((_elapsed/60)%60)) $((_elapsed%60)) >"$(tty)"
            fi
            sleep 0.25
        done

        # Return to the begin of the line after completion (the spinner will be overwritten)
        printf "\r" >"$(tty)"

        # Restore cursor visibility
        tput cnorm > /dev/tty
    fi
}

analyze_pihole_log() {
  echo_current_diagnostic "Pi-hole log"
  local pihole_log_permissions
  local queryLogging

  queryLogging="$(get_ftl_conf_value "dns.queryLogging")"
  if [[ "${queryLogging}" == "false" ]]; then
      # Inform user that logging has been disabled and pihole.log does not contain queries
      log_write "${INFO} Query logging is disabled"
      log_write ""
  fi

  pihole_log_permissions=$(ls -lhd "${PIHOLE_LOG}")
  log_write "${COL_GREEN}${pihole_log_permissions}${COL_NC}"
  head_tail_log "${PIHOLE_LOG}" 20
}

curl_to_tricorder() {
    # Users can submit their debug logs using curl (encrypted)
    log_write "    * Using ${COL_GREEN}curl${COL_NC} for transmission."
    # transmit the log via TLS and store the token returned in a variable
    tricorder_token=$(curl --silent --fail --show-error --upload-file ${PIHOLE_DEBUG_LOG} https://tricorder.pi-hole.net 2>&1)
    if [[ "${tricorder_token}" != "https://tricorder.pi-hole.net/"* ]]; then
        log_write "    * ${COL_GREEN}curl${COL_NC} failed, contact Pi-hole support for assistance."
        # Log curl error (if available)
        if [ -n "${tricorder_token}" ]; then
            log_write "    * Error message: ${COL_RED}${tricorder_token}${COL_NC}\\n"
            tricorder_token=""
        fi
    fi
}


upload_to_tricorder() {
    local username="pihole"
    # Set the permissions and owner
    chmod 640 ${PIHOLE_DEBUG_LOG}
    chown "$USER":"${username}" ${PIHOLE_DEBUG_LOG}

    # Let the user know debugging is complete with something strikingly visual
    log_write ""
    log_write "${COL_PURPLE}********************************************${COL_NC}"
    log_write "${COL_PURPLE}********************************************${COL_NC}"
    log_write "${TICK} ${COL_GREEN}** FINISHED DEBUGGING! **${COL_NC}\\n"

    # Provide information on what they should do with their token
    log_write "   * The debug log can be uploaded to tricorder.pi-hole.net for sharing with developers only."

    # If pihole -d is running automatically
    if [[ "${AUTOMATED}" ]]; then
        # let the user know
        log_write "${INFO} Debug script running in automated mode"
        # and then decide again which tool to use to submit it
        curl_to_tricorder
        # If we're not running in automated mode,
    else
        echo ""
        # give the user a choice of uploading it or not
        # Users can review the log file locally (or the output of the script since they are the same) and try to self-diagnose their problem
        read -r -p "[?] Would you like to upload the log? [y/N] " response
        case ${response} in
            # If they say yes, run our function for uploading the log
            [yY][eE][sS]|[yY]) curl_to_tricorder;;
            # If they choose no, just exit out of the script
            *) log_write "    * Log will ${COL_GREEN}NOT${COL_NC} be uploaded to tricorder.\\n    * A local copy of the debug log can be found at: ${COL_CYAN}${PIHOLE_DEBUG_LOG}${COL_NC}\\n";exit;
        esac
    fi
    # Check if tricorder.pi-hole.net is reachable and provide token
    # along with some additional useful information
    if [[ -n "${tricorder_token}" ]]; then
        # Again, try to make this visually striking so the user realizes they need to do something with this information
        # Namely, provide the Pi-hole devs with the token
        log_write ""
        log_write "${COL_PURPLE}*****************************************************************${COL_NC}"
        log_write "${COL_PURPLE}*****************************************************************${COL_NC}\\n"
        log_write "${TICK} Your debug token is: ${COL_GREEN}${tricorder_token}${COL_NC}"
        log_write "${INFO}${COL_RED} Logs are deleted 48 hours after upload.${COL_NC}\\n"
        log_write "${COL_PURPLE}*****************************************************************${COL_NC}"
        log_write "${COL_PURPLE}*****************************************************************${COL_NC}"
        log_write ""
        log_write "   * Provide the token above to the Pi-hole team for assistance at ${FORUMS_URL}"

    # If no token was generated
    else
        # Show an error and some help instructions
        log_write "${CROSS} ${COL_RED}There was an error uploading your debug log.${COL_NC}"
        log_write "   * Please try again or contact the Pi-hole team for assistance."
    fi
    # Finally, show where the log file is no matter the outcome of the function so users can look at it
    log_write "   * A local copy of the debug log can be found at: ${COL_CYAN}${PIHOLE_DEBUG_LOG}${COL_NC}\\n"
}

# Run through all the functions we made
make_temporary_log
initialize_debug
check_component_versions
# check_critical_program_versions
diagnose_operating_system
check_selinux
check_firewalld
hardware_check
disk_usage
check_ip_command
check_networking
check_name_resolution
check_dhcp_servers
process_status
ftl_full_status
analyze_ftl_db
analyze_gravity_list
show_groups
show_domainlist
show_clients
show_adlists
show_content_of_pihole_files
show_messages
parse_locale
analyze_pihole_log
copy_to_debug_log
upload_to_tricorder
