#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Generates pihole_debug.log to be used for troubleshooting.
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# shellcheck source=/dev/null

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

OBFUSCATED_PLACEHOLDER="<DOMAIN OBFUSCATED>"

# FAQ URLs for use in showing the debug log
FAQ_UPDATE_PI_HOLE="${COL_CYAN}https://discourse.pi-hole.net/t/how-do-i-update-pi-hole/249${COL_NC}"
FAQ_CHECKOUT_COMMAND="${COL_CYAN}https://discourse.pi-hole.net/t/the-pihole-command-with-examples/738#checkout${COL_NC}"
FAQ_HARDWARE_REQUIREMENTS="${COL_CYAN}https://docs.pi-hole.net/main/prerequisites/${COL_NC}"
FAQ_HARDWARE_REQUIREMENTS_PORTS="${COL_CYAN}https://docs.pi-hole.net/main/prerequisites/#ports${COL_NC}"
FAQ_HARDWARE_REQUIREMENTS_FIREWALLD="${COL_CYAN}https://docs.pi-hole.net/main/prerequisites/#firewalld${COL_NC}"
FAQ_GATEWAY="${COL_CYAN}https://discourse.pi-hole.net/t/why-is-a-default-gateway-important-for-pi-hole/3546${COL_NC}"
FAQ_ULA="${COL_CYAN}https://discourse.pi-hole.net/t/use-ipv6-ula-addresses-for-pi-hole/2127${COL_NC}"
FAQ_FTL_COMPATIBILITY="${COL_CYAN}https://github.com/pi-hole/FTL#compatibility-list${COL_NC}"
FAQ_BAD_ADDRESS="${COL_CYAN}https://discourse.pi-hole.net/t/why-do-i-see-bad-address-at-in-pihole-log/3972${COL_NC}"

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
#BLOCK_PAGE_DIRECTORY="${HTML_DIRECTORY}/pihole"
SHM_DIRECTORY="/dev/shm"

# Files required by Pi-hole
# https://discourse.pi-hole.net/t/what-files-does-pi-hole-use/1684
PIHOLE_CRON_FILE="${CRON_D_DIRECTORY}/pihole"

PIHOLE_DNS_CONFIG_FILE="${DNSMASQ_D_DIRECTORY}/01-pihole.conf"
PIHOLE_DHCP_CONFIG_FILE="${DNSMASQ_D_DIRECTORY}/02-pihole-dhcp.conf"
PIHOLE_WILDCARD_CONFIG_FILE="${DNSMASQ_D_DIRECTORY}/03-wildcard.conf"

WEB_SERVER_CONFIG_FILE="${WEB_SERVER_CONFIG_DIRECTORY}/lighttpd.conf"
WEB_SERVER_CUSTOM_CONFIG_FILE="${WEB_SERVER_CONFIG_DIRECTORY}/external.conf"

PIHOLE_INSTALL_LOG_FILE="${PIHOLE_DIRECTORY}/install.log"
PIHOLE_RAW_BLOCKLIST_FILES="${PIHOLE_DIRECTORY}/list.*"
PIHOLE_LOCAL_HOSTS_FILE="${PIHOLE_DIRECTORY}/local.list"
PIHOLE_LOGROTATE_FILE="${PIHOLE_DIRECTORY}/logrotate"
PIHOLE_SETUP_VARS_FILE="${PIHOLE_DIRECTORY}/setupVars.conf"
PIHOLE_FTL_CONF_FILE="${PIHOLE_DIRECTORY}/pihole-FTL.conf"

# Read the value of an FTL config key. The value is printed to stdout.
#
# Args:
# 1. The key to read
# 2. The default if the setting or config does not exist
get_ftl_conf_value() {
    local key=$1
    local default=$2
    local value

    # Obtain key=... setting from pihole-FTL.conf
    if [[ -e "$PIHOLE_FTL_CONF_FILE" ]]; then
        # Constructed to return nothing when
        # a) the setting is not present in the config file, or
        # b) the setting is commented out (e.g. "#DBFILE=...")
        value="$(sed -n -e "s/^\\s*$key=\\s*//p" ${PIHOLE_FTL_CONF_FILE})"
    fi

    # Test for missing value. Use default value in this case.
    if [[ -z "$value" ]]; then
        value="$default"
    fi

    echo "$value"
}

PIHOLE_GRAVITY_DB_FILE="$(get_ftl_conf_value "GRAVITYDB" "${PIHOLE_DIRECTORY}/gravity.db")"

PIHOLE_FTL_DB_FILE="$(get_ftl_conf_value "DBFILE" "${PIHOLE_DIRECTORY}/pihole-FTL.db")"

PIHOLE_COMMAND="${BIN_DIRECTORY}/pihole"
PIHOLE_COLTABLE_FILE="${BIN_DIRECTORY}/COL_TABLE"

FTL_PID="${RUN_DIRECTORY}/pihole-FTL.pid"
FTL_PORT="${RUN_DIRECTORY}/pihole-FTL.port"

PIHOLE_LOG="${LOG_DIRECTORY}/pihole.log"
PIHOLE_LOG_GZIPS="${LOG_DIRECTORY}/pihole.log.[0-9].*"
PIHOLE_DEBUG_LOG="${LOG_DIRECTORY}/pihole_debug.log"
PIHOLE_FTL_LOG="$(get_ftl_conf_value "LOGFILE" "${LOG_DIRECTORY}/pihole-FTL.log")"

PIHOLE_WEB_SERVER_ACCESS_LOG_FILE="${WEB_SERVER_LOG_DIRECTORY}/access.log"
PIHOLE_WEB_SERVER_ERROR_LOG_FILE="${WEB_SERVER_LOG_DIRECTORY}/error.log"

# An array of operating system "pretty names" that we officially support
# We can loop through the array at any time to see if it matches a value
#SUPPORTED_OS=("Raspbian" "Ubuntu" "Fedora" "Debian" "CentOS")

# Store Pi-hole's processes in an array for easy use and parsing
PIHOLE_PROCESSES=( "lighttpd" "pihole-FTL" )

# Store the required directories in an array so it can be parsed through
#REQUIRED_DIRECTORIES=("${CORE_GIT_DIRECTORY}"
#"${CRON_D_DIRECTORY}"
#"${DNSMASQ_D_DIRECTORY}"
#"${PIHOLE_DIRECTORY}"
#"${PIHOLE_SCRIPTS_DIRECTORY}"
#"${BIN_DIRECTORY}"
#"${RUN_DIRECTORY}"
#"${LOG_DIRECTORY}"
#"${WEB_SERVER_LOG_DIRECTORY}"
#"${WEB_SERVER_CONFIG_DIRECTORY}"
#"${HTML_DIRECTORY}"
#"${WEB_GIT_DIRECTORY}"
#"${BLOCK_PAGE_DIRECTORY}")

# Store the required directories in an array so it can be parsed through
REQUIRED_FILES=("${PIHOLE_CRON_FILE}"
"${PIHOLE_DNS_CONFIG_FILE}"
"${PIHOLE_DHCP_CONFIG_FILE}"
"${PIHOLE_WILDCARD_CONFIG_FILE}"
"${WEB_SERVER_CONFIG_FILE}"
"${WEB_SERVER_CUSTOM_CONFIG_FILE}"
"${PIHOLE_INSTALL_LOG_FILE}"
"${PIHOLE_RAW_BLOCKLIST_FILES}"
"${PIHOLE_LOCAL_HOSTS_FILE}"
"${PIHOLE_LOGROTATE_FILE}"
"${PIHOLE_SETUP_VARS_FILE}"
"${PIHOLE_FTL_CONF_FILE}"
"${PIHOLE_COMMAND}"
"${PIHOLE_COLTABLE_FILE}"
"${FTL_PID}"
"${FTL_PORT}"
"${PIHOLE_LOG}"
"${PIHOLE_LOG_GZIPS}"
"${PIHOLE_DEBUG_LOG}"
"${PIHOLE_FTL_LOG}"
"${PIHOLE_WEB_SERVER_ACCESS_LOG_FILE}"
"${PIHOLE_WEB_SERVER_ERROR_LOG_FILE}")

DISCLAIMER="This process collects information from your Pi-hole, and optionally uploads it to a unique and random directory on tricorder.pi-hole.net.

The intent of this script is to allow users to self-diagnose their installations.  This is accomplished by running tests against our software and providing the user with links to FAQ articles when a problem is detected.  Since we are a small team and Pi-hole has been growing steadily, it is our hope that this will help us spend more time on development.

NOTE: All log files auto-delete after 48 hours and ONLY the Pi-hole developers can access your data via the given token. We have taken these extra steps to secure your data and will work to further reduce any personal information gathered.
"

show_disclaimer(){
    log_write "${DISCLAIMER}"
}

source_setup_variables() {
    # Display the current test that is running
    log_write "\\n${COL_PURPLE}*** [ INITIALIZING ]${COL_NC} Sourcing setup variables"
    # If the variable file exists,
    if ls "${PIHOLE_SETUP_VARS_FILE}" 1> /dev/null 2>&1; then
        log_write "${INFO} Sourcing ${PIHOLE_SETUP_VARS_FILE}...";
        # source it
        source ${PIHOLE_SETUP_VARS_FILE}
    else
        # If it can't, show an error
        log_write "${PIHOLE_SETUP_VARS_FILE} ${COL_RED}does not exist or cannot be read.${COL_NC}"
    fi
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
    # Clear the screen so the debug log is readable
    clear
    show_disclaimer
    # Display that the debug process is beginning
    log_write "${COL_PURPLE}*** [ INITIALIZING ]${COL_NC}"
    # Timestamp the start of the log
    log_write "${INFO} $(date "+%Y-%m-%d:%H:%M:%S") debug log has been initialized."
}

# This is a function for visually displaying the curent test that is being run.
# Accepts one variable: the name of what is being diagnosed
# Colors do not show in the dasboard, but the icons do: [i], [✓], and [✗]
echo_current_diagnostic() {
    # Colors are used for visually distinguishing each test in the output
    # These colors do not show in the GUI, but the formatting will
    log_write "\\n${COL_PURPLE}*** [ DIAGNOSING ]:${COL_NC} ${1}"
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
        # We need to search for "AdminLTE" so store it in a variable as well
        #shellcheck disable=2034
        local search_term="AdminLTE"
    fi
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
            local remote_version
            remote_version=$(git describe --tags --abbrev=0);
            # What branch they are on
            local remote_branch
            remote_branch=$(git rev-parse --abbrev-ref HEAD);
            # The commit they are on
            local remote_commit
            remote_commit=$(git describe --long --dirty --tags --always)
            # Status of the repo
            local local_status
            local_status=$(git status -s)
            # echo this information out to the user in a nice format
            # If the current version matches what pihole -v produces, the user is up-to-date
            if [[ "${remote_version}" == "$(pihole -v | awk '/${search_term}/ {print $6}' | cut -d ')' -f1)" ]]; then
                log_write "${TICK} ${pihole_component}: ${COL_GREEN}${remote_version}${COL_NC}"
            # If not,
            else
                # echo the current version in yellow, signifying it's something to take a look at, but not a critical error
                # Also add a URL to an FAQ
                log_write "${INFO} ${pihole_component}: ${COL_YELLOW}${remote_version:-Untagged}${COL_NC} (${FAQ_UPDATE_PI_HOLE})"
            fi

            # Print the repo upstreams
            remotes=$(git remote -v)
            log_write "${INFO} Remotes: ${remotes//$'\n'/'\n             '}"

            # If the repo is on the master branch, they are on the stable codebase
            if [[ "${remote_branch}" == "master" ]]; then
                # so the color of the text is green
                log_write "${INFO} Branch: ${COL_GREEN}${remote_branch}${COL_NC}"
            # If it is any other branch, they are in a development branch
            else
                # So show that in yellow, signifying it's something to take a look at, but not a critical error
                log_write "${INFO} Branch: ${COL_YELLOW}${remote_branch:-Detached}${COL_NC} (${FAQ_CHECKOUT_COMMAND})"
            fi
            # echo the current commit
            log_write "${INFO} Commit: ${remote_commit}"
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
        # There is no git directory so check if the web interface was disabled
        local setup_vars_web_interface
        setup_vars_web_interface=$(< ${PIHOLE_SETUP_VARS_FILE} grep ^INSTALL_WEB_INTERFACE | cut -d '=' -f2)
        if [[ "${pihole_component}" == "Web" ]] && [[ "${setup_vars_web_interface}" == "false" ]]; then
            log_write "${INFO} ${pihole_component}: Disabled in setupVars.conf via INSTALL_WEB_INTERFACE=false"
        else
            # Return an error message
            log_write "${COL_RED}Directory ${git_dir} doesn't exist${COL_NC}"
            # and exit with a non zero code
            return 1
        fi
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
        log_write "${TICK} ${ftl_name}: ${COL_GREEN}${FTL_VERSION}${COL_NC}"
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
    # Create a local variable so this function can be safely reused
    local program_version
    echo_current_diagnostic "${program_name} version"
    # Evalutate the program we are checking, if it is any of the ones below, show the version
    case "${program_name}" in
        "lighttpd") program_version="$(${program_name} -v 2> /dev/null | head -n1 | cut -d '/' -f2 | cut -d ' ' -f1)"
                    ;;
        "php") program_version="$(${program_name} -v 2> /dev/null | head -n1 | cut -d '-' -f1 | cut -d ' ' -f2)"
                ;;
        # If a match is not found, show an error
        *) echo "Unrecognized program";
    esac
    # If the program does not have a version (the variable is empty)
    if [[ -z "${program_version}" ]]; then
        # Display and error
        log_write "${CROSS} ${COL_RED}${program_name} version could not be detected.${COL_NC}"
    else
        # Otherwise, display the version
        log_write "${INFO} ${program_version}"
    fi
}

# These are the most critical dependencies of Pi-hole, so we check for them
# and their versions, using the functions above.
check_critical_program_versions() {
    # Use the function created earlier and bundle them into one function that checks all the version numbers
    get_program_version "lighttpd"
    get_program_version "php"
}

os_check() {
    # This function gets a list of supported OS versions from a TXT record at versions.pi-hole.net
    # and determines whether or not the script is running on one of those systems
    local remote_os_domain valid_os valid_version detected_os detected_version cmdResult digReturnCode response
    remote_os_domain="versions.pi-hole.net"

    detected_os=$(grep "\bID\b" /etc/os-release | cut -d '=' -f2 | tr -d '"')
    detected_version=$(grep VERSION_ID /etc/os-release | cut -d '=' -f2 | tr -d '"')

    cmdResult="$(dig +short -t txt ${remote_os_domain} @ns1.pi-hole.net 2>&1; echo $?)"
    #Get the return code of the previous command (last line)
    digReturnCode="${cmdResult##*$'\n'}"

    # Extract dig response
    response="${cmdResult%%$'\n'*}"

    IFS=" " read -r -a supportedOS < <(echo "${response}" | tr -d '"')
    for distro_and_versions in "${supportedOS[@]}"
    do
        distro_part="${distro_and_versions%%=*}"
        versions_part="${distro_and_versions##*=}"

        if [[ "${detected_os^^}" =~ ${distro_part^^} ]]; then
            valid_os=true
            IFS="," read -r -a supportedVer <<<"${versions_part}"
            for version in "${supportedVer[@]}"
            do
                if [[ "${detected_version}" =~ $version ]]; then
                    valid_version=true
                    break
                fi
            done
            break
        fi
    done

    log_write "${INFO} dig return code:  ${digReturnCode}"
    log_write "${INFO} dig response:  ${response}"

    if [ "$valid_os" = true ]; then
        log_write "${TICK} Distro:  ${COL_GREEN}${detected_os^}${COL_NC}"

        if [ "$valid_version" = true ]; then
            log_write "${TICK} Version: ${COL_GREEN}${detected_version}${COL_NC}"
        else
            log_write "${CROSS} Version: ${COL_RED}${detected_version}${COL_NC}"
            log_write "${CROSS} Error: ${COL_RED}${detected_os^} is supported but version ${detected_version} is currently unsupported (${FAQ_HARDWARE_REQUIREMENTS})${COL_NC}"
        fi
    else
        log_write "${CROSS} Distro:  ${COL_RED}${detected_os^}${COL_NC}"
        log_write "${CROSS} Error: ${COL_RED}${detected_os^} is not a supported distro (${FAQ_HARDWARE_REQUIREMENTS})${COL_NC}"
    fi
}

diagnose_operating_system() {
    # error message in a variable so we can easily modify it later (or re-use it)
    local error_msg="Distribution unknown -- most likely you are on an unsupported platform and may run into issues."
    # Display the current test that is running
    echo_current_diagnostic "Operating system"

    # If there is a /etc/*release file, it's probably a supported operating system, so we can
    if ls /etc/*release 1> /dev/null 2>&1; then
        # display the attributes to the user from the function made earlier
        os_check
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
            local firewalld_expected_services=("http" "dns" "dhcp" "dhcpv6")
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
                # check FTL custom zone port: 4711
                local firewalld_ftl_zone_ports
                firewalld_ftl_zone_ports=$(firewall-cmd --zone=ftl --list-ports)
                if [[ "${firewalld_ftl_zone_ports}" =~ "4711/tcp" ]]; then
                    log_write "${TICK} ${COL_GREEN}  FTL Port 4711/tcp Detected${COL_NC}";
                else
                    log_write "${CROSS} ${COL_RED}  FTL Port 4711/tcp Not Detected${COL_NC} (${FAQ_HARDWARE_REQUIREMENTS_FIREWALLD})"
                fi
            else
                log_write "${CROSS} ${COL_RED}FTL Custom Zone Not Detected${COL_NC} (${FAQ_HARDWARE_REQUIREMENTS_FIREWALLD})"
            fi
        fi
    else
        log_write "${TICK} ${COL_GREEN}Firewalld service not detected${COL_NC}";
    fi
}

processor_check() {
    echo_current_diagnostic "Processor"
    # Store the processor type in a variable
    PROCESSOR=$(uname -m)
    # If it does not contain a value,
    if [[ -z "${PROCESSOR}" ]]; then
        # we couldn't detect it, so show an error
        PROCESSOR=$(lscpu | awk '/Architecture/ {print $2}')
        log_write "${CROSS} ${COL_RED}${PROCESSOR}${COL_NC} has not been tested with FTL, but may still work: (${FAQ_FTL_COMPATIBILITY})"
    else
        # Check if the architecture is currently supported for FTL
        case "${PROCESSOR}" in
            "amd64" | "x86_64") log_write "${TICK} ${COL_GREEN}${PROCESSOR}${COL_NC}"
                ;;
            "armv6l") log_write "${TICK} ${COL_GREEN}${PROCESSOR}${COL_NC}"
                ;;
            "armv6") log_write "${TICK} ${COL_GREEN}${PROCESSOR}${COL_NC}"
                ;;
            "armv7l") log_write "${TICK} ${COL_GREEN}${PROCESSOR}${COL_NC}"
                ;;
            "aarch64") log_write "${TICK} ${COL_GREEN}${PROCESSOR}${COL_NC}"
                ;;
            # Otherwise, show the processor type
            *) log_write "${INFO} ${PROCESSOR}";
        esac
    fi
}

parse_setup_vars() {
    echo_current_diagnostic "Setup variables"
    # If the file exists,
    if [[ -r "${PIHOLE_SETUP_VARS_FILE}" ]]; then
        # parse it
        parse_file "${PIHOLE_SETUP_VARS_FILE}"
    else
        # If not, show an error
        log_write "${CROSS} ${COL_RED}Could not read ${PIHOLE_SETUP_VARS_FILE}.${COL_NC}"
    fi
}

parse_locale() {
    local pihole_locale
    echo_current_diagnostic "Locale"
    pihole_locale="$(locale)"
    parse_file "${pihole_locale}"
}

does_ip_match_setup_vars() {
    # Check for IPv4 or 6
    local protocol="${1}"
    # IP address to check for
    local ip_address="${2}"
    # See what IP is in the setupVars.conf file
    local setup_vars_ip
    setup_vars_ip=$(< ${PIHOLE_SETUP_VARS_FILE} grep IPV"${protocol}"_ADDRESS | cut -d '=' -f2)
    # If it's an IPv6 address
    if [[ "${protocol}" == "6" ]]; then
        # Strip off the / (CIDR notation)
        if [[ "${ip_address%/*}" == "${setup_vars_ip%/*}" ]]; then
            # if it matches, show it in green
            log_write "   ${COL_GREEN}${ip_address%/*}${COL_NC} matches the IP found in ${PIHOLE_SETUP_VARS_FILE}"
        else
            # otherwise show it in red with an FAQ URL
            log_write "   ${COL_RED}${ip_address%/*}${COL_NC} does not match the IP found in ${PIHOLE_SETUP_VARS_FILE} (${FAQ_ULA})"
        fi

    else
        # if the protocol isn't 6, it's 4 so no need to strip the CIDR notation
        # since it exists in the setupVars.conf that way
        if [[ "${ip_address}" == "${setup_vars_ip}" ]]; then
            # show in green if it matches
            log_write "   ${COL_GREEN}${ip_address}${COL_NC} matches the IP found in ${PIHOLE_SETUP_VARS_FILE}"
        else
            # otherwise show it in red
            log_write "   ${COL_RED}${ip_address}${COL_NC} does not match the IP found in ${PIHOLE_SETUP_VARS_FILE} (${FAQ_ULA})"
        fi
    fi
}

detect_ip_addresses() {
    # First argument should be a 4 or a 6
    local protocol=${1}
    # Use ip to show the addresses for the chosen protocol
    # Store the values in an arry so they can be looped through
    # Get the lines that are in the file(s) and store them in an array for parsing later
    mapfile -t ip_addr_list < <(ip -"${protocol}" addr show dev "${PIHOLE_INTERFACE}" | awk -F ' ' '{ for(i=1;i<=NF;i++) if ($i ~ '/^inet/') print $(i+1) }')

    # If there is something in the IP address list,
    if [[ -n ${ip_addr_list[*]} ]]; then
        # Local iterator
        local i
        # Display the protocol and interface
        log_write "${TICK} IPv${protocol} address(es) bound to the ${PIHOLE_INTERFACE} interface:"
        # Since there may be more than one IP address, store them in an array
        for i in "${!ip_addr_list[@]}"; do
            # For each one in the list, print it out
            does_ip_match_setup_vars "${protocol}" "${ip_addr_list[$i]}"
        done
        # Print a blank line just for formatting
        log_write ""
    else
        # If there are no IPs detected, explain that the protocol is not configured
        log_write "${CROSS} ${COL_RED}No IPv${protocol} address(es) found on the ${PIHOLE_INTERFACE}${COL_NC} interface.\\n"
        return 1
    fi
    # If the protocol is v6
    if [[ "${protocol}" == "6" ]]; then
        # let the user know that as long as there is one green address, things should be ok
        log_write "   ^ Please note that you may have more than one IP address listed."
        log_write "   As long as one of them is green, and it matches what is in ${PIHOLE_SETUP_VARS_FILE}, there is no need for concern.\\n"
        log_write "   The link to the FAQ is for an issue that sometimes occurs when the IPv6 address changes, which is why we check for it.\\n"
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
    gateway="$(ip -"${protocol}" route | grep default | cut -d ' ' -f 3)"

    # If the gateway variable has a value (meaning a gateway was found),
    if [[ -n "${gateway}" ]]; then
        log_write "${INFO} Default IPv${protocol} gateway: ${gateway}"
        # Let the user know we will ping the gateway for a response
        log_write "   * Pinging ${gateway}..."
        # Try to quietly ping the gateway 3 times, with a timeout of 3 seconds, using numeric output only,
        # on the pihole interface, and tail the last three lines of the output
        # If pinging the gateway is not successful,
        if ! ${cmd} -c 1 -W 2 -n "${gateway}" -I "${PIHOLE_INTERFACE}" >/dev/null; then
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
        log_write "[${COL_GREEN}${port}${COL_NC}] is in use by ${COL_GREEN}${service_name}${COL_NC}"
    # Otherwise,
    else
        # Show the service name in red since it's non-standard
        log_write "[${COL_RED}${port}${COL_NC}] is in use by ${COL_RED}${service_name}${COL_NC} (${FAQ_HARDWARE_REQUIREMENTS_PORTS})"
    fi
}

check_required_ports() {
    echo_current_diagnostic "Ports in use"
    # Since Pi-hole needs 53, 80, and 4711, check what they are being used by
    # so we can detect any issues
    local resolver="pihole-FTL"
    local web_server="lighttpd"
    local ftl="pihole-FTL"
    # Create an array for these ports in use
    ports_in_use=()
    # Sort the addresses and remove duplicates
    while IFS= read -r line; do
        ports_in_use+=( "$line" )
    done < <( lsof -iTCP -sTCP:LISTEN -P -n +c 10 )

    # Now that we have the values stored,
    for i in "${!ports_in_use[@]}"; do
        # loop through them and assign some local variables
        local service_name
        service_name=$(echo "${ports_in_use[$i]}" | awk '{print $1}')
        local protocol_type
        protocol_type=$(echo "${ports_in_use[$i]}" | awk '{print $5}')
        local port_number
        port_number="$(echo "${ports_in_use[$i]}" | awk '{print $9}')"

        # Skip the line if it's the titles of the columns the lsof command produces
        if [[ "${service_name}" == COMMAND ]]; then
            continue
        fi
        # Use a case statement to determine if the right services are using the right ports
        case "$(echo "$port_number" | rev | cut -d: -f1 | rev)" in
            53) compare_port_to_service_assigned  "${resolver}" "${service_name}" 53
                ;;
            80) compare_port_to_service_assigned  "${web_server}" "${service_name}" 80
                ;;
            4711) compare_port_to_service_assigned  "${ftl}" "${service_name}" 4711
                ;;
            # If it's not a default port that Pi-hole needs, just print it out for the user to see
            *) log_write "${port_number} ${service_name} (${protocol_type})";
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
    # lighttpd.conf has a directive to show "X-Pi-hole: A black hole for Internet advertisements."
    # in the header of any Pi-holed domain
    # Similarly, it will show "X-Pi-hole: The Pi-hole Web interface is working!" if you view the header returned
    # when accessing the dashboard (i.e curl -I pi.hole/admin/)
    # server is operating correctly
    echo_current_diagnostic "Dashboard and block page"
    # Use curl -I to get the header and parse out just the X-Pi-hole one
    local block_page
    block_page=$(curl -Is localhost | awk '/X-Pi-hole/' | tr -d '\r')
    # Do it for the dashboard as well, as the header is different than above
    local dashboard
    dashboard=$(curl -Is localhost/admin/ | awk '/X-Pi-hole/' | tr -d '\r')
    # Store what the X-Header shoud be in variables for comparison later
    local block_page_working
    block_page_working="X-Pi-hole: A black hole for Internet advertisements."
    local dashboard_working
    dashboard_working="X-Pi-hole: The Pi-hole Web interface is working!"
    local full_curl_output_block_page
    full_curl_output_block_page="$(curl -Is localhost)"
    local full_curl_output_dashboard
    full_curl_output_dashboard="$(curl -Is localhost/admin/)"
    # If the X-header found by curl matches what is should be,
    if [[ $block_page == "$block_page_working" ]]; then
        # display a success message
        log_write "$TICK Block page X-Header: ${COL_GREEN}${block_page}${COL_NC}"
    else
        # Otherwise, show an error
        log_write "$CROSS Block page X-Header: ${COL_RED}X-Header does not match or could not be retrieved.${COL_NC}"
        log_write "${COL_RED}${full_curl_output_block_page}${COL_NC}"
    fi

    # Same logic applies to the dashbord as above, if the X-Header matches what a working system shoud have,
    if [[ $dashboard == "$dashboard_working" ]]; then
        # then we can show a success
        log_write "$TICK Web interface X-Header: ${COL_GREEN}${dashboard}${COL_NC}"
    else
        # Othewise, it's a failure since the X-Headers either don't exist or have been modified in some way
        log_write "$CROSS Web interface X-Header: ${COL_RED}X-Header does not match or could not be retrieved.${COL_NC}"
        log_write "${COL_RED}${full_curl_output_dashboard}${COL_NC}"
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
    # We need to test name resolution locally, via Pi-hole, and via a public resolver
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
        local pihole_address="${IP}"
        local remote_address="2001:4860:4860::8888"
        local record_type="AAAA"
    # Othwerwise, it should be 4
    else
        # so use the IPv4 values
        local local_address="127.0.0.1"
        local pihole_address="${IP}"
        local remote_address="8.8.8.8"
        local record_type="A"
    fi

    # Find a random blocked url that has not been whitelisted.
    # This helps emulate queries to different domains that a user might query
    # It will also give extra assurance that Pi-hole is correctly resolving and blocking domains
    local random_url
    random_url=$(sqlite3 "${PIHOLE_GRAVITY_DB_FILE}" "SELECT domain FROM vw_gravity ORDER BY RANDOM() LIMIT 1")

    # First, do a dig on localhost to see if Pi-hole can use itself to block a domain
    if local_dig=$(dig +tries=1 +time=2 -"${protocol}" "${random_url}" @${local_address} +short "${record_type}"); then
        # If it can, show success
        log_write "${TICK} ${random_url} ${COL_GREEN}is ${local_dig}${COL_NC} via ${COL_CYAN}localhost$COL_NC (${local_address})"
    else
        # Otherwise, show a failure
        log_write "${CROSS} ${COL_RED}Failed to resolve${COL_NC} ${random_url} via ${COL_RED}localhost${COL_NC} (${local_address})"
    fi

    # Next we need to check if Pi-hole can resolve a domain when the query is sent to it's IP address
    # This better emulates how clients will interact with Pi-hole as opposed to above where Pi-hole is
    # just asing itself locally
    # The default timeouts and tries are reduced in case the DNS server isn't working, so the user isn't waiting for too long

    # If Pi-hole can dig itself from it's IP (not the loopback address)
    if pihole_dig=$(dig +tries=1 +time=2 -"${protocol}" "${random_url}" @"${pihole_address}" +short "${record_type}"); then
        # show a success
        log_write "${TICK} ${random_url} ${COL_GREEN}is ${pihole_dig}${COL_NC} via ${COL_CYAN}Pi-hole${COL_NC} (${pihole_address})"
    else
        # Othewise, show a failure
        log_write "${CROSS} ${COL_RED}Failed to resolve${COL_NC} ${random_url} via ${COL_RED}Pi-hole${COL_NC} (${pihole_address})"
    fi

    # Finally, we need to make sure legitimate queries can out to the Internet using an external, public DNS server
    # We are using the static remote_url here instead of a random one because we know it works with IPv4 and IPv6
    if remote_dig=$(dig +tries=1 +time=2 -"${protocol}" "${remote_url}" @${remote_address} +short "${record_type}" | head -n1); then
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
        # If systemd
        if command -v systemctl &> /dev/null; then
            # get its status via systemctl
            local status_of_process
            status_of_process=$(systemctl is-active "${i}")
        else
            # Otherwise, use the service command and mock the output of `systemctl is-active`
            local status_of_process
            if service "${i}" status | grep -E 'is\srunning' &> /dev/null; then
                status_of_process="active"
            else
                status_of_process="inactive"
            fi
        fi
        # and print it out to the user
        if [[ "${status_of_process}" == "active" ]]; then
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
    else
      log_write "${INFO} systemctl:  command not found"
    fi
}

make_array_from_file() {
    local filename="${1}"
    # The second argument can put a limit on how many line should be read from the file
    # Since some of the files are so large, this is helpful to limit the output
    local limit=${2}
    # A local iterator for testing if we are at the limit above
    local i=0
    # Set the array to be empty so we can start fresh when the function is used
    local file_content=()
    # If the file is a directory
    if [[ -d "${filename}" ]]; then
        # do nothing since it cannot be parsed
        :
    else
        # Otherwise, read the file line by line
        while IFS= read -r line;do
            # Othwerise, strip out comments and blank lines
            new_line=$(echo "${line}" | sed -e 's/^\s*#.*$//' -e '/^$/d')
            # If the line still has content (a non-zero value)
            if [[ -n "${new_line}" ]]; then
                # Put it into the array
                file_content+=("${new_line}")
            else
                # Otherwise, it's a blank line or comment, so do nothing
                :
            fi
            # Increment the iterator +1
            i=$((i+1))
            # but if the limit of lines we want to see is exceeded
            if [[ -z ${limit} ]]; then
                # do nothing
                :
            elif [[ $i -eq ${limit} ]]; then
                break
            fi
        done < "${filename}"
        # Now the we have made an array of the file's content
        for each_line in "${file_content[@]}"; do
            # Print each line
            # At some point, we may want to check the file line-by-line, so that's the reason for an array
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
    local file_info
    if [[ -f "$filename" ]]; then
        #shellcheck disable=SC2016
        IFS=$'\r\n' command eval 'file_info=( $(cat "${filename}") )'
    else
        read -r -a file_info <<< "$filename"
    fi
    # Set a named variable for better readability
    local file_lines
    # For each line in the file,
    for file_lines in "${file_info[@]}"; do
        if [[ ! -z "${file_lines}" ]]; then
            # don't include the Web password hash
            [[ "${file_lines}" =~ ^\#.*$  || ! "${file_lines}" || "${file_lines}" == "WEBPASSWORD="* ]] && continue
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
    # Set the first argument passed to this function as a named variable for better readability
    local directory="${1}"
    # Display the current test that is running
    echo_current_diagnostic "contents of ${COL_CYAN}${directory}${COL_NC}"
    # For each file in the directory,
    for filename in ${directory}; do
        # check if exists first; if it does,
        if ls "${filename}" 1> /dev/null 2>&1; then
            # do nothing
            :
        else
            # Otherwise, show an error
            log_write "${COL_RED}${directory} does not exist.${COL_NC}"
        fi
    done
}

list_files_in_dir() {
    # Set the first argument passed to this function as a named variable for better readability
    local dir_to_parse="${1}"
    # Store the files found in an array
    mapfile -t files_found < <(ls "${dir_to_parse}")
    # For each file in the array,
    for each_file in "${files_found[@]}"; do
        if [[ -d "${dir_to_parse}/${each_file}" ]]; then
            # If it's a directory, do nothing
            :
        elif [[ "${dir_to_parse}/${each_file}" == "${PIHOLE_DEBUG_LOG}" ]] || \
            [[ "${dir_to_parse}/${each_file}" == "${PIHOLE_RAW_BLOCKLIST_FILES}" ]] || \
            [[ "${dir_to_parse}/${each_file}" == "${PIHOLE_INSTALL_LOG_FILE}" ]] || \
            [[ "${dir_to_parse}/${each_file}" == "${PIHOLE_SETUP_VARS_FILE}" ]] || \
            [[ "${dir_to_parse}/${each_file}" == "${PIHOLE_LOG}" ]] || \
            [[ "${dir_to_parse}/${each_file}" == "${PIHOLE_WEB_SERVER_ACCESS_LOG_FILE}" ]] || \
            [[ "${dir_to_parse}/${each_file}" == "${PIHOLE_LOG_GZIPS}" ]]; then
            :
        elif [[ "${dir_to_parse}" == "${SHM_DIRECTORY}" ]]; then
            # SHM file - we do not want to see the content, but we want to see the files and their sizes
            log_write "$(ls -ld "${dir_to_parse}"/"${each_file}")"
        else
            # Then, parse the file's content into an array so each line can be analyzed if need be
            for i in "${!REQUIRED_FILES[@]}"; do
                if [[ "${dir_to_parse}/${each_file}" == "${REQUIRED_FILES[$i]}" ]]; then
                    # display the filename
                    log_write "\\n${COL_GREEN}$(ls -ld "${dir_to_parse}"/"${each_file}")${COL_NC}"
                    # Check if the file we want to view has a limit (because sometimes we just need a little bit of info from the file, not the entire thing)
                    case "${dir_to_parse}/${each_file}" in
                        # If it's Web server error log, give the first and last 25 lines
                        "${PIHOLE_WEB_SERVER_ERROR_LOG_FILE}") head_tail_log "${dir_to_parse}/${each_file}" 25
                            ;;
                        # Same for the FTL log
                        "${PIHOLE_FTL_LOG}") head_tail_log "${dir_to_parse}/${each_file}" 35
                            ;;
                        # parse the file into an array in case we ever need to analyze it line-by-line
                        *) make_array_from_file "${dir_to_parse}/${each_file}";
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
    dir_check "${directory}"
    # if it does, list the files in it
    list_files_in_dir "${directory}"
}

show_content_of_pihole_files() {
    # Show the content of the files in each of Pi-hole's folders
    show_content_of_files_in_dir "${PIHOLE_DIRECTORY}"
    show_content_of_files_in_dir "${DNSMASQ_D_DIRECTORY}"
    show_content_of_files_in_dir "${WEB_SERVER_CONFIG_DIRECTORY}"
    show_content_of_files_in_dir "${CRON_D_DIRECTORY}"
    show_content_of_files_in_dir "${WEB_SERVER_LOG_DIRECTORY}"
    show_content_of_files_in_dir "${LOG_DIRECTORY}"
    show_content_of_files_in_dir "${SHM_DIRECTORY}"
}

head_tail_log() {
    # The file being processed
    local filename="${1}"
    # The number of lines to use for head and tail
    local qty="${2}"
    local head_line
    local tail_line
    # Put the current Internal Field Separator into another variable so it can be restored later
    OLD_IFS="$IFS"
    # Get the lines that are in the file(s) and store them in an array for parsing later
    IFS=$'\r\n'
    local log_head=()
    mapfile -t log_head < <(head -n "${qty}" "${filename}")
    log_write "   ${COL_CYAN}-----head of $(basename "${filename}")------${COL_NC}"
    for head_line in "${log_head[@]}"; do
        log_write "   ${head_line}"
    done
    log_write ""
    local log_tail=()
    mapfile -t log_tail < <(tail -n "${qty}" "${filename}")
    log_write "   ${COL_CYAN}-----tail of $(basename "${filename}")------${COL_NC}"
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
        sqlite3 "${PIHOLE_GRAVITY_DB_FILE}" \
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
        sqlite3 "${PIHOLE_FTL_DB_FILE}" \
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
    echo_current_diagnostic "Discovering active DHCP servers (takes 10 seconds)"

    OLD_IFS="$IFS"
    IFS=$'\n'
    local entries=()
    mapfile -t entries < <(pihole-FTL dhcp-discover)

    for line in "${entries[@]}"; do
        log_write "   ${line}"
    done

    IFS="$OLD_IFS"
}

show_groups() {
    show_db_entries "Groups" "SELECT id,CASE enabled WHEN '0' THEN '   0' WHEN '1' THEN '      1' ELSE enabled END enabled,name,datetime(date_added,'unixepoch','localtime') date_added,datetime(date_modified,'unixepoch','localtime') date_modified,description FROM \"group\"" "4 7 50 19 19 50"
}

show_adlists() {
    show_db_entries "Adlists" "SELECT id,CASE enabled WHEN '0' THEN '   0' WHEN '1' THEN '      1' ELSE enabled END enabled,GROUP_CONCAT(adlist_by_group.group_id) group_ids,address,datetime(date_added,'unixepoch','localtime') date_added,datetime(date_modified,'unixepoch','localtime') date_modified,comment FROM adlist LEFT JOIN adlist_by_group ON adlist.id = adlist_by_group.adlist_id GROUP BY id;" "4 7 12 100 19 19 50"
}

show_domainlist() {
    show_db_entries "Domainlist (0/1 = exact white-/blacklist, 2/3 = regex white-/blacklist)" "SELECT id,CASE type WHEN '0' THEN '0   ' WHEN '1' THEN ' 1  ' WHEN '2' THEN '  2 ' WHEN '3' THEN '   3' ELSE type END type,CASE enabled WHEN '0' THEN '   0' WHEN '1' THEN '      1' ELSE enabled END enabled,GROUP_CONCAT(domainlist_by_group.group_id) group_ids,domain,datetime(date_added,'unixepoch','localtime') date_added,datetime(date_modified,'unixepoch','localtime') date_modified,comment FROM domainlist LEFT JOIN domainlist_by_group ON domainlist.id = domainlist_by_group.domainlist_id GROUP BY id;" "4 4 7 12 100 19 19 50"
}

show_clients() {
    show_db_entries "Clients" "SELECT id,GROUP_CONCAT(client_by_group.group_id) group_ids,ip,datetime(date_added,'unixepoch','localtime') date_added,datetime(date_modified,'unixepoch','localtime') date_modified,comment FROM client LEFT JOIN client_by_group ON client.id = client_by_group.client_id GROUP BY id;" "4 12 100 19 19 50"
}

show_messages() {
    show_FTL_db_entries "Pi-hole diagnosis messages" "SELECT id,datetime(timestamp,'unixepoch','localtime') timestamp,type,message,blob1,blob2,blob3,blob4,blob5 FROM message;" "4 19 20 60 20 20 20 20 20"
}

analyze_gravity_list() {
    echo_current_diagnostic "Gravity List and Database"

    local gravity_permissions
    gravity_permissions=$(ls -ld "${PIHOLE_GRAVITY_DB_FILE}")
    log_write "${COL_GREEN}${gravity_permissions}${COL_NC}"

    show_db_entries "Info table" "SELECT property,value FROM info" "20 40"
    gravity_updated_raw="$(sqlite3 "${PIHOLE_GRAVITY_DB_FILE}" "SELECT value FROM info where property = 'updated'")"
    gravity_updated="$(date -d @"${gravity_updated_raw}")"
    log_write "   Last gravity run finished at: ${COL_CYAN}${gravity_updated}${COL_NC}"
    log_write ""

    OLD_IFS="$IFS"
    IFS=$'\r\n'
    local gravity_sample=()
    mapfile -t gravity_sample < <(sqlite3 "${PIHOLE_GRAVITY_DB_FILE}" "SELECT domain FROM vw_gravity LIMIT 10")
    log_write "   ${COL_CYAN}----- First 10 Gravity Domains -----${COL_NC}"

    for line in "${gravity_sample[@]}"; do
        log_write "   ${line}"
    done

    log_write ""
    IFS="$OLD_IFS"
}

analyze_pihole_log() {
    echo_current_diagnostic "Pi-hole log"
    local head_line
    # Put the current Internal Field Separator into another variable so it can be restored later
    OLD_IFS="$IFS"
    # Get the lines that are in the file(s) and store them in an array for parsing later
    IFS=$'\r\n'
    local pihole_log_permissions
    pihole_log_permissions=$(ls -ld "${PIHOLE_LOG}")
    log_write "${COL_GREEN}${pihole_log_permissions}${COL_NC}"
    local pihole_log_head=()
    mapfile -t pihole_log_head < <(head -n 20 ${PIHOLE_LOG})
    log_write "   ${COL_CYAN}-----head of $(basename ${PIHOLE_LOG})------${COL_NC}"
    local error_to_check_for
    local line_to_obfuscate
    local obfuscated_line
    for head_line in "${pihole_log_head[@]}"; do
        # A common error in the pihole.log is when there is a non-hosts formatted file
        # that the DNS server is attempting to read.  Since it's not formatted
        # correctly, there will be an entry for "bad address at line n"
        # So we can check for that here and highlight it in red so the user can see it easily
        error_to_check_for=$(echo "${head_line}" | grep 'bad address at')
        # Some users may not want to have the domains they visit sent to us
        # To that end, we check for lines in the log that would contain a domain name
        line_to_obfuscate=$(echo "${head_line}" | grep ': query\|: forwarded\|: reply')
        # If the variable contains a value, it found an error in the log
        if [[ -n ${error_to_check_for} ]]; then
            # So we can print it in red to make it visible to the user
            log_write "   ${CROSS} ${COL_RED}${head_line}${COL_NC} (${FAQ_BAD_ADDRESS})"
        else
            # If the variable does not a value (the current default behavior), so do not obfuscate anything
            if [[ -z ${OBFUSCATE} ]]; then
                log_write "   ${head_line}"
            # Othwerise, a flag was passed to this command to obfuscate domains in the log
            else
                # So first check if there are domains in the log that should be obfuscated
                if [[ -n ${line_to_obfuscate} ]]; then
                    # If there are, we need to use awk to replace only the domain name (the 6th field in the log)
                    # so we substitute the domain for the placeholder value
                    obfuscated_line=$(echo "${line_to_obfuscate}" | awk -v placeholder="${OBFUSCATED_PLACEHOLDER}" '{sub($6,placeholder); print $0}')
                    log_write "   ${obfuscated_line}"
                else
                    log_write "   ${head_line}"
                fi
            fi
        fi
    done
    log_write ""
    # Set the IFS back to what it was
    IFS="$OLD_IFS"
}

tricorder_use_nc_or_curl() {
    # Users can submit their debug logs using nc (unencrypted) or curl (encrypted) if available
    # Check for curl first since encryption is a good thing
    if command -v curl &> /dev/null; then
        # If the command exists,
        log_write "    * Using ${COL_GREEN}curl${COL_NC} for transmission."
        # transmit he log via TLS and store the token returned in a variable
        tricorder_token=$(curl --silent --upload-file ${PIHOLE_DEBUG_LOG} https://tricorder.pi-hole.net:${TRICORDER_SSL_PORT_NUMBER})
        if [ -z "${tricorder_token}" ]; then
         # curl failed, fallback to nc
         log_write "    * ${COL_GREEN}curl${COL_NC} failed, falling back to ${COL_YELLOW}netcat${COL_NC} for transmission."
         tricorder_token=$(< ${PIHOLE_DEBUG_LOG} nc tricorder.pi-hole.net ${TRICORDER_NC_PORT_NUMBER})
        fi
    # Otherwise,
    else
        # use net cat
        log_write "${INFO} Using ${COL_YELLOW}netcat${COL_NC} for transmission."
        # Save the token returned by our server in a variable
        tricorder_token=$(< ${PIHOLE_DEBUG_LOG} nc tricorder.pi-hole.net ${TRICORDER_NC_PORT_NUMBER})
    fi
}


upload_to_tricorder() {
    local username="pihole"
    # Set the permissions and owner
    chmod 644 ${PIHOLE_DEBUG_LOG}
    chown "$USER":"${username}" ${PIHOLE_DEBUG_LOG}

    # Let the user know debugging is complete with something strikingly visual
    log_write ""
    log_write "${COL_PURPLE}********************************************${COL_NC}"
    log_write "${COL_PURPLE}********************************************${COL_NC}"
    log_write "${TICK} ${COL_GREEN}** FINISHED DEBUGGING! **${COL_NC}\\n"

    # Provide information on what they should do with their token
    log_write "    * The debug log can be uploaded to tricorder.pi-hole.net for sharing with developers only."
    log_write "    * For more information, see: ${TRICORDER_CONTEST}"
    log_write "    * If available, we'll use openssl to upload the log, otherwise it will fall back to netcat."
    # If pihole -d is running automatically (usually through the dashboard)
    if [[ "${AUTOMATED}" ]]; then
        # let the user know
        log_write "${INFO} Debug script running in automated mode"
        # and then decide again which tool to use to submit it
        tricorder_use_nc_or_curl
        # If we're not running in automated mode,
    else
        echo ""
        # give the user a choice of uploading it or not
        # Users can review the log file locally (or the output of the script since they are the same) and try to self-diagnose their problem
        read -r -p "[?] Would you like to upload the log? [y/N] " response
        case ${response} in
            # If they say yes, run our function for uploading the log
            [yY][eE][sS]|[yY]) tricorder_use_nc_or_curl;;
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
        log_write "${COL_PURPLE}***********************************${COL_NC}"
        log_write "${COL_PURPLE}***********************************${COL_NC}"
        log_write "${TICK} Your debug token is: ${COL_GREEN}${tricorder_token}${COL_NC}"
        log_write "${COL_PURPLE}***********************************${COL_NC}"
        log_write "${COL_PURPLE}***********************************${COL_NC}"
        log_write ""
        log_write "   * Provide the token above to the Pi-hole team for assistance at"
        log_write "   * ${FORUMS_URL}"
        log_write "   * Your log will self-destruct on our server after ${COL_RED}48 hours${COL_NC}."
    # If no token was generated
    else
        # Show an error and some help instructions
        log_write "${CROSS}  ${COL_RED}There was an error uploading your debug log.${COL_NC}"
        log_write "   * Please try again or contact the Pi-hole team for assistance."
    fi
    # Finally, show where the log file is no matter the outcome of the function so users can look at it
    log_write "   * A local copy of the debug log can be found at: ${COL_CYAN}${PIHOLE_DEBUG_LOG}${COL_NC}\\n"
}

# Run through all the functions we made
make_temporary_log
initialize_debug
# setupVars.conf needs to be sourced before the networking so the values are
# available to the other functions
source_setup_variables
check_component_versions
check_critical_program_versions
diagnose_operating_system
check_selinux
check_firewalld
processor_check
check_networking
check_name_resolution
check_dhcp_servers
process_status
ftl_full_status
parse_setup_vars
check_x_headers
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
