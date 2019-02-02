#!/usr/bin/env bash
# shellcheck disable=SC1090

# Pi-hole: A black hole for Internet advertisements
# (c) 2017-2018 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Installs and Updates Pi-hole
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# pi-hole.net/donate
#
# Install with this command (from your Linux machine):
#
# curl -sSL https://install.pi-hole.net | bash

# -e option instructs bash to immediately exit if any command [1] has a non-zero exit status
# We do not want users to end up with a partially working install, so we exit the script
# instead of continuing the installation with something broken
set -e

######## VARIABLES #########
# For better maintainability, we store as much information that can change in variables
# This allows us to make a change in one place that can propagate to all instances of the variable
# These variables should all be GLOBAL variables, written in CAPS
# Local variables will be in lowercase and will exist only within functions
# It's still a work in progress, so you may see some variance in this guideline until it is complete

# Location for final installation log storage
installLogLoc=/etc/pihole/install.log
# This is an important file as it contains information specific to the machine it's being installed on
setupVars=/etc/pihole/setupVars.conf
# Pi-hole uses lighttpd as a Web server, and this is the config file for it
# shellcheck disable=SC2034
lighttpdConfig=/etc/lighttpd/lighttpd.conf
# This is a file used for the colorized output
coltable=/opt/pihole/COL_TABLE

# We store several other directories and
webInterfaceGitUrl="https://github.com/pi-hole/AdminLTE.git"
webInterfaceDir="/var/www/html/admin"
piholeGitUrl="https://github.com/pi-hole/pi-hole.git"
PI_HOLE_LOCAL_REPO="/etc/.pihole"
# These are the names of pi-holes files, stored in an array
PI_HOLE_FILES=(chronometer list piholeDebug piholeLogFlush setupLCD update version gravity uninstall webpage)
# This directory is where the Pi-hole scripts will be installed
PI_HOLE_INSTALL_DIR="/opt/pihole"
PI_HOLE_CONFIG_DIR="/etc/pihole"
useUpdateVars=false

adlistFile="/etc/pihole/adlists.list"
regexFile="/etc/pihole/regex.list"
# Pi-hole needs an IP address; to begin, these variables are empty since we don't know what the IP is until
# this script can run
IPV4_ADDRESS=""
IPV6_ADDRESS=""
# By default, query logging is enabled and the dashboard is set to be installed
QUERY_LOGGING=true
INSTALL_WEB_INTERFACE=true
PRIVACY_LEVEL=0

if [ -z "${USER}" ]; then
  USER="$(id -un)"
fi


# Find the rows and columns will default to 80x24 if it can not be detected
screen_size=$(stty size || printf '%d %d' 24 80)
# Set rows variable to contain first number
printf -v rows '%d' "${screen_size%% *}"
# Set columns variable to contain second number
printf -v columns '%d' "${screen_size##* }"

# Divide by two so the dialogs take up half of the screen, which looks nice.
r=$(( rows / 2 ))
c=$(( columns / 2 ))
# Unless the screen is tiny
r=$(( r < 20 ? 20 : r ))
c=$(( c < 70 ? 70 : c ))

######## Undocumented Flags. Shhh ########
# These are undocumented flags; some of which we can use when repairing an installation
# The runUnattended flag is one example of this
skipSpaceCheck=false
reconfigure=false
runUnattended=false
INSTALL_WEB_SERVER=true
# Check arguments for the undocumented flags
for var in "$@"; do
    case "$var" in
        "--reconfigure" ) reconfigure=true;;
        "--i_do_not_follow_recommendations" ) skipSpaceCheck=true;;
        "--unattended" ) runUnattended=true;;
        "--disable-install-webserver" ) INSTALL_WEB_SERVER=false;;
    esac
done

# If the color table file exists,
if [[ -f "${coltable}" ]]; then
    # source it
    source ${coltable}
# Otherwise,
else
    # Set these values so the installer can still run in color
    COL_NC='\e[0m' # No Color
    COL_LIGHT_GREEN='\e[1;32m'
    COL_LIGHT_RED='\e[1;31m'
    TICK="[${COL_LIGHT_GREEN}✓${COL_NC}]"
    CROSS="[${COL_LIGHT_RED}✗${COL_NC}]"
    INFO="[i]"
    # shellcheck disable=SC2034
    DONE="${COL_LIGHT_GREEN} done!${COL_NC}"
    OVER="\\r\\033[K"
fi

# Define global binary variable
binary="tbd"

# A simple function that just echoes out our logo in ASCII format
# This lets users know that it is a Pi-hole, LLC product
show_ascii_berry() {
  echo -e "
        ${COL_LIGHT_GREEN}.;;,.
        .ccccc:,.
         :cccclll:.      ..,,
          :ccccclll.   ;ooodc
           'ccll:;ll .oooodc
             .;cll.;;looo:.
                 ${COL_LIGHT_RED}.. ','.
                .',,,,,,'.
              .',,,,,,,,,,.
            .',,,,,,,,,,,,....
          ....''',,,,,,,'.......
        .........  ....  .........
        ..........      ..........
        ..........      ..........
        .........  ....  .........
          ........,,,,,,,'......
            ....',,,,,,,,,,,,.
               .',,,,,,,,,'.
                .',,,,,,'.
                  ..'''.${COL_NC}
"
}

is_command() {
    # Checks for existence of string passed in as only function argument.
    # Exit value of 0 when exists, 1 if not exists. Value is the result
    # of the `command` shell built-in call.
    local check_command="$1"

    command -v "${check_command}" >/dev/null 2>&1
}

# Compatibility
distro_check() {
# If apt-get is installed, then we know it's part of the Debian family
if is_command apt-get ; then
    # Set some global variables here
    # We don't set them earlier since the family might be Red Hat, so these values would be different
    PKG_MANAGER="apt-get"
    # A variable to store the command used to update the package cache
    UPDATE_PKG_CACHE="${PKG_MANAGER} update"
    # An array for something...
    PKG_INSTALL=(${PKG_MANAGER} --yes --no-install-recommends install)
    # grep -c will return 1 retVal on 0 matches, block this throwing the set -e with an OR TRUE
    PKG_COUNT="${PKG_MANAGER} -s -o Debug::NoLocking=true upgrade | grep -c ^Inst || true"
    # Some distros vary slightly so these fixes for dependencies may apply
    # on Ubuntu 18.04.1 LTS we need to add the universe repository to gain access to dialog and dhcpcd5
    APT_SOURCES="/etc/apt/sources.list"
    if awk 'BEGIN{a=1;b=0}/bionic main/{a=0}/bionic.*universe/{b=1}END{exit a + b}' ${APT_SOURCES}; then
        if ! whiptail --defaultno --title "Dependencies Require Update to Allowed Repositories" --yesno "Would you like to enable 'universe' repository?\\n\\nThis repository is required by the following packages:\\n\\n- dhcpcd5\\n- dialog" ${r} ${c}; then
            printf "  %b Aborting installation: dependencies could not be installed.\\n" "${CROSS}"
            exit # exit the installer
        else
            printf "  %b Enabling universe package repository for Ubuntu Bionic\\n" "${INFO}"
            cp ${APT_SOURCES} ${APT_SOURCES}.backup # Backup current repo list
            printf "  %b Backed up current configuration to %s\\n" "${TICK}" "${APT_SOURCES}.backup"
            add-apt-repository universe
            printf "  %b Enabled %s\\n" "${TICK}" "'universe' repository"
        fi
    fi
    # Debian 7 doesn't have iproute2 so if the dry run install is successful,
    if ${PKG_MANAGER} install --dry-run iproute2 > /dev/null 2>&1; then
        # we can install it
        iproute_pkg="iproute2"
    # Otherwise,
    else
        # use iproute
        iproute_pkg="iproute"
    fi
    # Check for and determine version number (major and minor) of current php install
    if is_command php ; then
        printf "  %b Existing PHP installation detected : PHP version %s\\n" "${INFO}" "$(php <<< "<?php echo PHP_VERSION ?>")"
        printf -v phpInsMajor "%d" "$(php <<< "<?php echo PHP_MAJOR_VERSION ?>")"
        printf -v phpInsMinor "%d" "$(php <<< "<?php echo PHP_MINOR_VERSION ?>")"
        # Is installed php version 7.0 or greater
        if [ "${phpInsMajor}" -ge 7 ]; then
            phpInsNewer=true
        fi
    fi
    # Check if installed php is v 7.0, or newer to determine packages to install
    if [[ "$phpInsNewer" != true ]]; then
        # Prefer the php metapackage if it's there
        if ${PKG_MANAGER} install --dry-run php > /dev/null 2>&1; then
            phpVer="php"
        # fall back on the php5 packages
        else
            phpVer="php5"
        fi
    else
        # Newer php is installed, its common, cgi & sqlite counterparts are deps
        phpVer="php$phpInsMajor.$phpInsMinor"
    fi
    # We also need the correct version for `php-sqlite` (which differs across distros)
    if ${PKG_MANAGER} install --dry-run ${phpVer}-sqlite3 > /dev/null 2>&1; then
        phpSqlite="sqlite3"
    else
        phpSqlite="sqlite"
    fi
    # Since our install script is so large, we need several other programs to successfully get a machine provisioned
    # These programs are stored in an array so they can be looped through later
    INSTALLER_DEPS=(apt-utils dialog debconf dhcpcd5 git ${iproute_pkg} whiptail)
    # Pi-hole itself has several dependencies that also need to be installed
    PIHOLE_DEPS=(cron curl dnsutils iputils-ping lsof netcat psmisc sudo unzip wget idn2 sqlite3 libcap2-bin dns-root-data resolvconf libcap2)
    # The Web dashboard has some that also need to be installed
    # It's useful to separate the two since our repos are also setup as "Core" code and "Web" code
    PIHOLE_WEB_DEPS=(lighttpd ${phpVer}-common ${phpVer}-cgi ${phpVer}-${phpSqlite})
    # The Web server user,
    LIGHTTPD_USER="www-data"
    # group,
    LIGHTTPD_GROUP="www-data"
    # and config file
    LIGHTTPD_CFG="lighttpd.conf.debian"

    # A function to check...
    test_dpkg_lock() {
        # An iterator used for counting loop iterations
        i=0
        # fuser is a program to show which processes use the named files, sockets, or filesystems
        # So while the command is true
        while fuser /var/lib/dpkg/lock >/dev/null 2>&1 ; do
            # Wait half a second
            sleep 0.5
            # and increase the iterator
            ((i=i+1))
        done
        # Always return success, since we only return if there is no
        # lock (anymore)
        return 0
    }

# If apt-get is not found, check for rpm to see if it's a Red Hat family OS
elif is_command rpm ; then
    # Then check if dnf or yum is the package manager
    if is_command dnf ; then
        PKG_MANAGER="dnf"
    else
        PKG_MANAGER="yum"
    fi

    # Fedora and family update cache on every PKG_INSTALL call, no need for a separate update.
    UPDATE_PKG_CACHE=":"
    PKG_INSTALL=(${PKG_MANAGER} install -y)
    PKG_COUNT="${PKG_MANAGER} check-update | egrep '(.i686|.x86|.noarch|.arm|.src)' | wc -l"
    INSTALLER_DEPS=(dialog git iproute newt procps-ng which)
    PIHOLE_DEPS=(bind-utils cronie curl findutils nmap-ncat sudo unzip wget libidn2 psmisc sqlite libcap)
    PIHOLE_WEB_DEPS=(lighttpd lighttpd-fastcgi php-common php-cli php-pdo)
    LIGHTTPD_USER="lighttpd"
    LIGHTTPD_GROUP="lighttpd"
    LIGHTTPD_CFG="lighttpd.conf.fedora"
    # If the host OS is Fedora,
    if grep -qiE 'fedora|fedberry' /etc/redhat-release; then
        # all required packages should be available by default with the latest fedora release
        # ensure 'php-json' is installed on Fedora (installed as dependency on CentOS7 + Remi repository)
        PIHOLE_WEB_DEPS+=('php-json')
    # or if host OS is CentOS,
    elif grep -qiE 'centos|scientific' /etc/redhat-release; then
        # Pi-Hole currently supports CentOS 7+ with PHP7+
        SUPPORTED_CENTOS_VERSION=7
        SUPPORTED_CENTOS_PHP_VERSION=7
        # Check current CentOS major release version
        CURRENT_CENTOS_VERSION=$(grep -oP '(?<= )[0-9]+(?=\.)' /etc/redhat-release)
        # Check if CentOS version is supported
        if [[ $CURRENT_CENTOS_VERSION -lt $SUPPORTED_CENTOS_VERSION ]]; then
            printf "  %b CentOS %s is not supported.\\n" "${CROSS}" "${CURRENT_CENTOS_VERSION}"
            printf "      Please update to CentOS release %s or later.\\n" "${SUPPORTED_CENTOS_VERSION}"
            # exit the installer
            exit
        fi
        # on CentOS we need to add the EPEL repository to gain access to Fedora packages
        EPEL_PKG="epel-release"
        rpm -q ${EPEL_PKG} &> /dev/null || rc=$?
        if [[ $rc -ne 0 ]]; then
            printf "  %b Enabling EPEL package repository (https://fedoraproject.org/wiki/EPEL)\\n" "${INFO}"
            "${PKG_INSTALL[@]}" ${EPEL_PKG} &> /dev/null
            printf "  %b Installed %s\\n" "${TICK}" "${EPEL_PKG}"
        fi

        # The default php on CentOS 7.x is 5.4 which is EOL
        # Check if the version of PHP available via installed repositories is >= to PHP 7
        AVAILABLE_PHP_VERSION=$(${PKG_MANAGER} info php | grep -i version | grep -o '[0-9]\+' | head -1)
        if [[ $AVAILABLE_PHP_VERSION -ge $SUPPORTED_CENTOS_PHP_VERSION ]]; then
            # Since PHP 7 is available by default, install via default PHP package names
            : # do nothing as PHP is current
        else
            REMI_PKG="remi-release"
            REMI_REPO="remi-php72"
            rpm -q ${REMI_PKG} &> /dev/null || rc=$?
        if [[ $rc -ne 0 ]]; then
            # The PHP version available via default repositories is older than version 7
            if ! whiptail --defaultno --title "PHP 7 Update (recommended)" --yesno "PHP 7.x is recommended for both security and language features.\\nWould you like to install PHP7 via Remi's RPM repository?\\n\\nSee: https://rpms.remirepo.net for more information" ${r} ${c}; then
                # User decided to NOT update PHP from REMI, attempt to install the default available PHP version
                printf "  %b User opt-out of PHP 7 upgrade on CentOS. Deprecated PHP may be in use.\\n" "${INFO}"
                : # continue with unsupported php version
            else
                printf "  %b Enabling Remi's RPM repository (https://rpms.remirepo.net)\\n" "${INFO}"
                "${PKG_INSTALL[@]}" "https://rpms.remirepo.net/enterprise/${REMI_PKG}-$(rpm -E '%{rhel}').rpm" &> /dev/null
                # enable the PHP 7 repository via yum-config-manager (provided by yum-utils)
                "${PKG_INSTALL[@]}" "yum-utils" &> /dev/null
                yum-config-manager --enable ${REMI_REPO} &> /dev/null
                printf "  %b Remi's RPM repository has been enabled for PHP7\\n" "${TICK}"
                # trigger an install/update of PHP to ensure previous version of PHP is updated from REMI
                if "${PKG_INSTALL[@]}" "php-cli" &> /dev/null; then
                    printf "  %b PHP7 installed/updated via Remi's RPM repository\\n" "${TICK}"
                else
                    printf "  %b There was a problem updating to PHP7 via Remi's RPM repository\\n" "${CROSS}"
                    exit 1
                fi
            fi
        fi
    fi
    else
        # Warn user of unsupported version of Fedora or CentOS
        if ! whiptail --defaultno --title "Unsupported RPM based distribution" --yesno "Would you like to continue installation on an unsupported RPM based distribution?\\n\\nPlease ensure the following packages have been installed manually:\\n\\n- lighttpd\\n- lighttpd-fastcgi\\n- PHP version 7+" ${r} ${c}; then
            printf "  %b Aborting installation due to unsupported RPM based distribution\\n" "${CROSS}"
            exit # exit the installer
        else
            printf "  %b Continuing installation with unsupported RPM based distribution\\n" "${INFO}"
        fi
    fi

# If neither apt-get or yum/dnf package managers were found
else
    # it's not an OS we can support,
    printf "  %b OS distribution not supported\\n" "${CROSS}"
    # so exit the installer
    exit
fi
}

# A function for checking if a directory is a git repository
is_repo() {
    # Use a named, local variable instead of the vague $1, which is the first argument passed to this function
    # These local variables should always be lowercase
    local directory="${1}"
    # A local variable for the current directory
    local curdir
    # A variable to store the return code
    local rc
    # Assign the current directory variable by using pwd
    curdir="${PWD}"
    # If the first argument passed to this function is a directory,
    if [[ -d "${directory}" ]]; then
        # move into the directory
        cd "${directory}"
        # Use git to check if the directory is a repo
        # git -C is not used here to support git versions older than 1.8.4
        git status --short &> /dev/null || rc=$?
    # If the command was not successful,
    else
        # Set a non-zero return code if directory does not exist
        rc=1
    fi
    # Move back into the directory the user started in
    cd "${curdir}"
    # Return the code; if one is not set, return 0
    return "${rc:-0}"
}

# A function to clone a repo
make_repo() {
    # Set named variables for better readability
    local directory="${1}"
    local remoteRepo="${2}"
    # The message to display when this function is running
    str="Clone ${remoteRepo} into ${directory}"
    # Display the message and use the color table to preface the message with an "info" indicator
    printf "  %b %s..." "${INFO}" "${str}"
    # If the directory exists,
    if [[ -d "${directory}" ]]; then
        # delete everything in it so git can clone into it
        rm -rf "${directory}"
    fi
    # Clone the repo and return the return code from this command
    git clone -q --depth 1 "${remoteRepo}" "${directory}" &> /dev/null || return $?
    # Show a colored message showing it's status
    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
    # Always return 0? Not sure this is correct
    return 0
}

# We need to make sure the repos are up-to-date so we can effectively install Clean out the directory if it exists for git to clone into
update_repo() {
    # Use named, local variables
    # As you can see, these are the same variable names used in the last function,
    # but since they are local, their scope does not go beyond this function
    # This helps prevent the wrong value from being assigned if you were to set the variable as a GLOBAL one
    local directory="${1}"
    local curdir

    # A variable to store the message we want to display;
    # Again, it's useful to store these in variables in case we need to reuse or change the message;
    # we only need to make one change here
    local str="Update repo in ${1}"

    # Make sure we know what directory we are in so we can move back into it
    curdir="${PWD}"
    # Move into the directory that was passed as an argument
    cd "${directory}" &> /dev/null || return 1
    # Let the user know what's happening
    printf "  %b %s..." "${INFO}" "${str}"
    # Stash any local commits as they conflict with our working code
    git stash --all --quiet &> /dev/null || true # Okay for stash failure
    git clean --quiet --force -d || true # Okay for already clean directory
    # Pull the latest commits
    git pull --quiet &> /dev/null || return $?
    # Show a completion message
    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
    # Move back into the original directory
    cd "${curdir}" &> /dev/null || return 1
    return 0
}

# A function that combines the functions previously made
getGitFiles() {
    # Setup named variables for the git repos
    # We need the directory
    local directory="${1}"
    # as well as the repo URL
    local remoteRepo="${2}"
    # A local variable containing the message to be displayed
    local str="Check for existing repository in ${1}"
    # Show the message
    printf "  %b %s..." "${INFO}" "${str}"
    # Check if the directory is a repository
    if is_repo "${directory}"; then
        # Show that we're checking it
        printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
        # Update the repo, returning an error message on failure
        update_repo "${directory}" || { printf "\\n  %b: Could not update local repository. Contact support.%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }
    # If it's not a .git repo,
    else
        # Show an error
        printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
        # Attempt to make the repository, showing an error on failure
        make_repo "${directory}" "${remoteRepo}" || { printf "\\n  %bError: Could not update local repository. Contact support.%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }
    fi
    # echo a blank line
    echo ""
    # and return success?
    return 0
}

# Reset a repo to get rid of any local changed
resetRepo() {
    # Use named variables for arguments
    local directory="${1}"
    # Move into the directory
    cd "${directory}" &> /dev/null || return 1
    # Store the message in a variable
    str="Resetting repository within ${1}..."
    # Show the message
    printf "  %b %s..." "${INFO}" "${str}"
    # Use git to remove the local changes
    git reset --hard &> /dev/null || return $?
    # And show the status
    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
    # Returning success anyway?
    return 0
}

find_IPv4_information() {
    # Detects IPv4 address used for communication to WAN addresses.
    # Accepts no arguments, returns no values.

    # Named, local variables
    local route
    local IPv4bare

    # Find IP used to route to outside world by checking the the route to Google's public DNS server
    route=$(ip route get 8.8.8.8)

    # Get just the interface IPv4 address
    # shellcheck disable=SC2059,SC2086
    # disabled as we intentionally want to split on whitespace and have printf populate
    # the variable with just the first field.
    printf -v IPv4bare "$(printf ${route#*src })"
    # Get the default gateway IPv4 address (the way to reach the Internet)
    # shellcheck disable=SC2059,SC2086
    printf -v IPv4gw "$(printf ${route#*via })"

    if ! valid_ip "${IPv4bare}" ; then
        IPv4bare="127.0.0.1"
    fi

    # Append the CIDR notation to the IP address, if valid_ip fails this should return 127.0.0.1/8
    IPV4_ADDRESS=$(ip -oneline -family inet address show | grep "${IPv4bare}" |  awk '{print $4}' | awk 'END {print}')
}

# Get available interfaces that are UP
get_available_interfaces() {
    # There may be more than one so it's all stored in a variable
    availableInterfaces=$(ip --oneline link show up | grep -v "lo" | awk '{print $2}' | cut -d':' -f1 | cut -d'@' -f1)
}

# A function for displaying the dialogs the user sees when first running the installer
welcomeDialogs() {
    # Display the welcome dialog using an appropriately sized window via the calculation conducted earlier in the script
    whiptail --msgbox --backtitle "Welcome" --title "Pi-hole automated installer" "\\n\\nThis installer will transform your device into a network-wide ad blocker!" ${r} ${c}

    # Request that users donate if they enjoy the software since we all work on it in our free time
    whiptail --msgbox --backtitle "Plea" --title "Free and open source" "\\n\\nThe Pi-hole is free, but powered by your donations:  http://pi-hole.net/donate" ${r} ${c}

    # Explain the need for a static address
    whiptail --msgbox --backtitle "Initiating network interface" --title "Static IP Needed" "\\n\\nThe Pi-hole is a SERVER so it needs a STATIC IP ADDRESS to function properly.

In the next section, you can choose to use your current network settings (DHCP) or to manually edit them." ${r} ${c}
}

# We need to make sure there is enough space before installing, so there is a function to check this
verifyFreeDiskSpace() {
    # 50MB is the minimum space needed (45MB install (includes web admin bootstrap/jquery libraries etc) + 5MB one day of logs.)
    # - Fourdee: Local ensures the variable is only created, and accessible within this function/void. Generally considered a "good" coding practice for non-global variables.
    local str="Disk space check"
    # Required space in KB
    local required_free_kilobytes=51200
    # Calculate existing free space on this machine
    local existing_free_kilobytes
    existing_free_kilobytes=$(df -Pk | grep -m1 '\/$' | awk '{print $4}')

    # If the existing space is not an integer,
    if ! [[ "${existing_free_kilobytes}" =~ ^([0-9])+$ ]]; then
        # show an error that we can't determine the free space
        printf "  %b %s\\n" "${CROSS}" "${str}"
        printf "  %b Unknown free disk space! \\n" "${INFO}"
        printf "      We were unable to determine available free disk space on this system.\\n"
        printf "      You may override this check, however, it is not recommended.\\n"
        printf "      The option '%b--i_do_not_follow_recommendations%b' can override this.\\n" "${COL_LIGHT_RED}" "${COL_NC}"
        printf "      e.g: curl -L https://install.pi-hole.net | bash /dev/stdin %b<option>%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"
        # exit with an error code
        exit 1
    # If there is insufficient free disk space,
    elif [[ "${existing_free_kilobytes}" -lt "${required_free_kilobytes}" ]]; then
        # show an error message
        printf "  %b %s\\n" "${CROSS}" "${str}"
        printf "  %b Your system disk appears to only have %s KB free\\n" "${INFO}" "${existing_free_kilobytes}"
        printf "      It is recommended to have a minimum of %s KB to run the Pi-hole\\n" "${required_free_kilobytes}"
        # if the vcgencmd command exists,
        if is_command vcgencmd ; then
            # it's probably a Raspbian install, so show a message about expanding the filesystem
            printf "      If this is a new install you may need to expand your disk\\n"
            printf "      Run 'sudo raspi-config', and choose the 'expand file system' option\\n"
            printf "      After rebooting, run this installation again\\n"
            printf "      e.g: curl -L https://install.pi-hole.net | bash\\n"
        fi
        # Show there is not enough free space
        printf "\\n      %bInsufficient free space, exiting...%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"
        # and exit with an error
        exit 1
    # Otherwise,
    else
        # Show that we're running a disk space check
        printf "  %b %s\\n" "${TICK}" "${str}"
    fi
}

# A function that let's the user pick an interface to use with Pi-hole
chooseInterface() {
    # Turn the available interfaces into an array so it can be used with a whiptail dialog
    local interfacesArray=()
    # Number of available interfaces
    local interfaceCount
    # Whiptail variable storage
    local chooseInterfaceCmd
    # Temporary Whiptail options storage
    local chooseInterfaceOptions
    # Loop sentinel variable
    local firstLoop=1

    # Find out how many interfaces are available to choose from
    interfaceCount=$(wc -l <<< "${availableInterfaces}")

    # If there is one interface,
    if [[ "${interfaceCount}" -eq 1 ]]; then
        # Set it as the interface to use since there is no other option
        PIHOLE_INTERFACE="${availableInterfaces}"
    # Otherwise,
    else
        # While reading through the available interfaces
        while read -r line; do
            # use a variable to set the option as OFF to begin with
            mode="OFF"
            # If it's the first loop,
            if [[ "${firstLoop}" -eq 1 ]]; then
                # set this as the interface to use (ON)
                firstLoop=0
                mode="ON"
            fi
            # Put all these interfaces into an array
            interfacesArray+=("${line}" "available" "${mode}")
        # Feed the available interfaces into this while loop
        done <<< "${availableInterfaces}"
        # The whiptail command that will be run, stored in a variable
        chooseInterfaceCmd=(whiptail --separate-output --radiolist "Choose An Interface (press space to select)" ${r} ${c} ${interfaceCount})
        # Now run the command using the interfaces saved into the array
        chooseInterfaceOptions=$("${chooseInterfaceCmd[@]}" "${interfacesArray[@]}" 2>&1 >/dev/tty) || \
        # If the user chooses Cancel, exit
        { printf "  %bCancel was selected, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }
        # For each interface
        for desiredInterface in ${chooseInterfaceOptions}; do
            # Set the one the user selected as the interface to use
            PIHOLE_INTERFACE=${desiredInterface}
            # and show this information to the user
            printf "  %b Using interface: %s\\n" "${INFO}" "${PIHOLE_INTERFACE}"
        done
    fi
}

# This lets us prefer ULA addresses over GUA
# This caused problems for some users when their ISP changed their IPv6 addresses
# See https://github.com/pi-hole/pi-hole/issues/1473#issuecomment-301745953
testIPv6() {
    # first will contain fda2 (ULA)
    printf -v first "%s" "${1%%:*}"
    # value1 will contain 253 which is the decimal value corresponding to 0xfd
    value1=$(( (0x$first)/256 ))
    # will contain 162 which is the decimal value corresponding to 0xa2
    value2=$(( (0x$first)%256 ))
    # the ULA test is testing for fc00::/7 according to RFC 4193
    if (( (value1&254)==252 )); then
        # echoing result to calling function as return value
        echo "ULA"
    fi
    # the GUA test is testing for 2000::/3 according to RFC 4291
    if (( (value1&112)==32 )); then
        # echoing result to calling function as return value
        echo "GUA"
    fi
    # the LL test is testing for fe80::/10 according to RFC 4193
    if (( (value1)==254 )) && (( (value2&192)==128 )); then
        # echoing result to calling function as return value
        echo "Link-local"
    fi
}

# A dialog for showing the user about IPv6 blocking
useIPv6dialog() {
    # Determine the IPv6 address used for blocking
    IPV6_ADDRESSES=($(ip -6 address | grep 'scope global' | awk '{print $2}'))

    # For each address in the array above, determine the type of IPv6 address it is
    for i in "${IPV6_ADDRESSES[@]}"; do
        # Check if it's ULA, GUA, or LL by using the function created earlier
        result=$(testIPv6 "$i")
        # If it's a ULA address, use it and store it as a global variable
        [[ "${result}" == "ULA" ]] && ULA_ADDRESS="${i%/*}"
        # If it's a GUA address, we can still use it si store it as a global variable
        [[ "${result}" == "GUA" ]] && GUA_ADDRESS="${i%/*}"
    done

    # Determine which address to be used: Prefer ULA over GUA or don't use any if none found
    # If the ULA_ADDRESS contains a value,
    if [[ ! -z "${ULA_ADDRESS}" ]]; then
        # set the IPv6 address to the ULA address
        IPV6_ADDRESS="${ULA_ADDRESS}"
        # Show this info to the user
        printf "  %b Found IPv6 ULA address, using it for blocking IPv6 ads\\n" "${INFO}"
    # Otherwise, if the GUA_ADDRESS has a value,
    elif [[ ! -z "${GUA_ADDRESS}" ]]; then
        # Let the user know
        printf "  %b Found IPv6 GUA address, using it for blocking IPv6 ads\\n" "${INFO}"
        # And assign it to the global variable
        IPV6_ADDRESS="${GUA_ADDRESS}"
    # If none of those work,
    else
        # explain that IPv6 blocking will not be used
        printf "  %b Unable to find IPv6 ULA/GUA address, IPv6 adblocking will not be enabled\\n" "${INFO}"
        # So set the variable to be empty
        IPV6_ADDRESS=""
    fi

    # If the IPV6_ADDRESS contains a value
    if [[ ! -z "${IPV6_ADDRESS}" ]]; then
        # Display that IPv6 is supported and will be used
        whiptail --msgbox --backtitle "IPv6..." --title "IPv6 Supported" "$IPV6_ADDRESS will be used to block ads." ${r} ${c}
    fi
}

# A function to check if we should use IPv4 and/or IPv6 for blocking ads
use4andor6() {
    # Named local variables
    local useIPv4
    local useIPv6
    # Let use select IPv4 and/or IPv6 via a checklist
    cmd=(whiptail --separate-output --checklist "Select Protocols (press space to select)" ${r} ${c} 2)
    # In an array, show the options available:
    # IPv4 (on by default)
    options=(IPv4 "Block ads over IPv4" on
    # or IPv6 (on by default if available)
    IPv6 "Block ads over IPv6" on)
    # In a variable, show the choices available; exit if Cancel is selected
    choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty) || { printf "  %bCancel was selected, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }
    # For each choice available,
    for choice in ${choices}
    do
        # Set the values to true
        case ${choice} in
        IPv4  )   useIPv4=true;;
        IPv6  )   useIPv6=true;;
        esac
    done
    # If IPv4 is to be used,
    if [[ "${useIPv4}" ]]; then
        # Run our function to get the information we need
        find_IPv4_information
        getStaticIPv4Settings
        setStaticIPv4
    fi
    # If IPv6 is to be used,
    if [[ "${useIPv6}" ]]; then
        # Run our function to get this information
        useIPv6dialog
    fi
    # Echo the information to the user
    printf "  %b IPv4 address: %s\\n" "${INFO}" "${IPV4_ADDRESS}"
    printf "  %b IPv6 address: %s\\n" "${INFO}" "${IPV6_ADDRESS}"
    # If neither protocol is selected,
    if [[ ! "${useIPv4}" ]] && [[ ! "${useIPv6}" ]]; then
        # Show an error in red
        printf "  %bError: Neither IPv4 or IPv6 selected%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"
        # and exit with an error
        exit 1
    fi
}

#
getStaticIPv4Settings() {
    # Local, named variables
    local ipSettingsCorrect
    # Ask if the user wants to use DHCP settings as their static IP
    # This is useful for users that are using DHCP reservations; then we can just use the information gathered via our functions
    if whiptail --backtitle "Calibrating network interface" --title "Static IP Address" --yesno "Do you want to use your current network settings as a static address?
          IP address:    ${IPV4_ADDRESS}
          Gateway:       ${IPv4gw}" ${r} ${c}; then
        # If they choose yes, let the user know that the IP address will not be available via DHCP and may cause a conflict.
        whiptail --msgbox --backtitle "IP information" --title "FYI: IP Conflict" "It is possible your router could still try to assign this IP to a device, which would cause a conflict.  But in most cases the router is smart enough to not do that.
If you are worried, either manually set the address, or modify the DHCP reservation pool so it does not include the IP you want.
It is also possible to use a DHCP reservation, but if you are going to do that, you might as well set a static address." ${r} ${c}
    # Nothing else to do since the variables are already set above
    else
    # Otherwise, we need to ask the user to input their desired settings.
    # Start by getting the IPv4 address (pre-filling it with info gathered from DHCP)
    # Start a loop to let the user enter their information with the chance to go back and edit it if necessary
    until [[ "${ipSettingsCorrect}" = True ]]; do

        # Ask for the IPv4 address
        IPV4_ADDRESS=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 address" --inputbox "Enter your desired IPv4 address" ${r} ${c} "${IPV4_ADDRESS}" 3>&1 1>&2 2>&3) || \
        # Cancelling IPv4 settings window
        { ipSettingsCorrect=False; echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}"; exit 1; }
        printf "  %b Your static IPv4 address: %s\\n" "${INFO}" "${IPV4_ADDRESS}"

        # Ask for the gateway
        IPv4gw=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 gateway (router)" --inputbox "Enter your desired IPv4 default gateway" ${r} ${c} "${IPv4gw}" 3>&1 1>&2 2>&3) || \
        # Cancelling gateway settings window
        { ipSettingsCorrect=False; echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}"; exit 1; }
        printf "  %b Your static IPv4 gateway: %s\\n" "${INFO}" "${IPv4gw}"

        # Give the user a chance to review their settings before moving on
        if whiptail --backtitle "Calibrating network interface" --title "Static IP Address" --yesno "Are these settings correct?
            IP address: ${IPV4_ADDRESS}
            Gateway:    ${IPv4gw}" ${r} ${c}; then
                # After that's done, the loop ends and we move on
                ipSettingsCorrect=True
        else
            # If the settings are wrong, the loop continues
            ipSettingsCorrect=False
        fi
    done
    # End the if statement for DHCP vs. static
    fi
}

# configure networking via dhcpcd
setDHCPCD() {
    # check if the IP is already in the file
    if grep -q "${IPV4_ADDRESS}" /etc/dhcpcd.conf; then
        printf "  %b Static IP already configured\\n" "${INFO}"
    # If it's not,
    else
        # we can append these lines to dhcpcd.conf to enable a static IP
        echo "interface ${PIHOLE_INTERFACE}
        static ip_address=${IPV4_ADDRESS}
        static routers=${IPv4gw}
        static domain_name_servers=127.0.0.1" | tee -a /etc/dhcpcd.conf >/dev/null
        # Then use the ip command to immediately set the new address
        ip addr replace dev "${PIHOLE_INTERFACE}" "${IPV4_ADDRESS}"
        # Also give a warning that the user may need to reboot their system
        printf "  %b Set IP address to %s \\n  You may need to restart after the install is complete\\n" "${TICK}" "${IPV4_ADDRESS%/*}"
    fi
}

# configure networking ifcfg-xxxx file found at /etc/sysconfig/network-scripts/
# this function requires the full path of an ifcfg file passed as an argument
setIFCFG() {
    # Local, named variables
    local IFCFG_FILE
    local IPADDR
    local CIDR
    IFCFG_FILE=$1
    printf -v IPADDR "%s" "${IPV4_ADDRESS%%/*}"
    # check if the desired IP is already set
    if grep -Eq "${IPADDR}(\\b|\\/)" "${IFCFG_FILE}"; then
        printf "  %b Static IP already configured\\n" "${INFO}"
    # Otherwise,
    else
        # Put the IP in variables without the CIDR notation
        printf -v CIDR "%s" "${IPV4_ADDRESS##*/}"
        # Backup existing interface configuration:
        cp "${IFCFG_FILE}" "${IFCFG_FILE}".pihole.orig
        # Build Interface configuration file using the GLOBAL variables we have
        {
        echo "# Configured via Pi-hole installer"
        echo "DEVICE=$PIHOLE_INTERFACE"
        echo "BOOTPROTO=none"
        echo "ONBOOT=yes"
        echo "IPADDR=$IPADDR"
        echo "PREFIX=$CIDR"
        echo "GATEWAY=$IPv4gw"
        echo "DNS1=$PIHOLE_DNS_1"
        echo "DNS2=$PIHOLE_DNS_2"
        echo "USERCTL=no"
        }> "${IFCFG_FILE}"
        # Use ip to immediately set the new address
        ip addr replace dev "${PIHOLE_INTERFACE}" "${IPV4_ADDRESS}"
        # If NetworkMangler command line interface exists and ready to mangle,
        if is_command nmcli && nmcli general status &> /dev/null; then
            # Tell NetworkManagler to read our new sysconfig file
            nmcli con load "${IFCFG_FILE}" > /dev/null
        fi
        # Show a warning that the user may need to restart
        printf "  %b Set IP address to %s\\n  You may need to restart after the install is complete\\n" "${TICK}" "${IPV4_ADDRESS%%/*}"
    fi
}

setStaticIPv4() {
    # Local, named variables
    local IFCFG_FILE
    local CONNECTION_NAME
    # For the Debian family, if dhcpcd.conf exists,
    if [[ -f "/etc/dhcpcd.conf" ]]; then
        # configure networking via dhcpcd
        setDHCPCD
        return 0
    fi
    # If a DHCPCD config file was not found, check for an ifcfg config file based on interface name
    if [[ -f "/etc/sysconfig/network-scripts/ifcfg-${PIHOLE_INTERFACE}" ]];then
        # If it exists,
        IFCFG_FILE=/etc/sysconfig/network-scripts/ifcfg-${PIHOLE_INTERFACE}
        setIFCFG "${IFCFG_FILE}"
        return 0
    fi
    # if an ifcfg config does not exists for the interface name, try the connection name via network manager
    if is_command nmcli && nmcli general status &> /dev/null; then
        CONNECTION_NAME=$(nmcli dev show "${PIHOLE_INTERFACE}" | grep 'GENERAL.CONNECTION' | cut -d: -f2 | sed 's/^System//' | xargs | tr ' ' '_')
        if [[ -f "/etc/sysconfig/network-scripts/ifcfg-${CONNECTION_NAME}" ]];then
            # If it exists,
            IFCFG_FILE=/etc/sysconfig/network-scripts/ifcfg-${CONNECTION_NAME}
            setIFCFG "${IFCFG_FILE}"
            return 0
        fi
    fi
    # If previous conditions failed, show an error and exit
    printf "  %b Warning: Unable to locate configuration file to set static IPv4 address\\n" "${INFO}"
    exit 1
}

# Check an IP address to see if it is a valid one
valid_ip() {
    # Local, named variables
    local ip=${1}
    local stat=1

    # If the IP matches the format xxx.xxx.xxx.xxx,
    if [[ "${ip}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # Save the old Internal Field Separator in a variable
        OIFS=$IFS
        # and set the new one to a dot (period)
        IFS='.'
        # Put the IP into an array
        ip=(${ip})
        # Restore the IFS to what it was
        IFS=${OIFS}
        ## Evaluate each octet by checking if it's less than or equal to 255 (the max for each octet)
        [[ "${ip[0]}" -le 255 && "${ip[1]}" -le 255 \
        && "${ip[2]}" -le 255 && "${ip[3]}" -le 255 ]]
        # Save the exit code
        stat=$?
    fi
    # Return the exit code
    return ${stat}
}

# A function to choose the upstream DNS provider(s)
setDNS() {
    # Local, named variables
    local DNSSettingsCorrect

    # In an array, list the available upstream providers
    DNSChooseOptions=(Google ""
        OpenDNS ""
        Level3 ""
        Comodo ""
        DNSWatch ""
        Quad9 ""
        FamilyShield ""
        Cloudflare ""
        Custom "")
    # In a whiptail dialog, show the options
    DNSchoices=$(whiptail --separate-output --menu "Select Upstream DNS Provider. To use your own, select Custom." ${r} ${c} 7 \
    "${DNSChooseOptions[@]}" 2>&1 >/dev/tty) || \
    # exit if Cancel is selected
    { printf "  %bCancel was selected, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }

    # Display the selection
    printf "  %b Using " "${INFO}"
    # Depending on the user's choice, set the GLOBAl variables to the IP of the respective provider
    case ${DNSchoices} in
        Google)
            printf "Google DNS servers\\n"
            PIHOLE_DNS_1="8.8.8.8"
            PIHOLE_DNS_2="8.8.4.4"
            ;;
        OpenDNS)
            printf "OpenDNS servers\\n"
            PIHOLE_DNS_1="208.67.222.222"
            PIHOLE_DNS_2="208.67.220.220"
            ;;
        Level3)
            printf "Level3 servers\\n"
            PIHOLE_DNS_1="4.2.2.1"
            PIHOLE_DNS_2="4.2.2.2"
            ;;
        Comodo)
            printf "Comodo Secure servers\\n"
            PIHOLE_DNS_1="8.26.56.26"
            PIHOLE_DNS_2="8.20.247.20"
            ;;
        DNSWatch)
            printf "DNS.WATCH servers\\n"
            PIHOLE_DNS_1="84.200.69.80"
            PIHOLE_DNS_2="84.200.70.40"
            ;;
        Quad9)
            printf "Quad9 servers\\n"
            PIHOLE_DNS_1="9.9.9.9"
            PIHOLE_DNS_2="149.112.112.112"
            ;;
        FamilyShield)
            printf "FamilyShield servers\\n"
            PIHOLE_DNS_1="208.67.222.123"
            PIHOLE_DNS_2="208.67.220.123"
            ;;
        Cloudflare)
            printf "Cloudflare servers\\n"
            PIHOLE_DNS_1="1.1.1.1"
            PIHOLE_DNS_2="1.0.0.1"
            ;;
        Custom)
            # Until the DNS settings are selected,
            until [[ "${DNSSettingsCorrect}" = True ]]; do
                #
                strInvalid="Invalid"
                # If the first
                if [[ ! "${PIHOLE_DNS_1}" ]]; then
                    # and second upstream servers do not exist
                    if [[ ! "${PIHOLE_DNS_2}" ]]; then
                        prePopulate=""
                    # Otherwise,
                    else
                        prePopulate=", ${PIHOLE_DNS_2}"
                    fi
                elif  [[ "${PIHOLE_DNS_1}" ]] && [[ ! "${PIHOLE_DNS_2}" ]]; then
                    prePopulate="${PIHOLE_DNS_1}"
                elif [[ "${PIHOLE_DNS_1}" ]] && [[ "${PIHOLE_DNS_2}" ]]; then
                    prePopulate="${PIHOLE_DNS_1}, ${PIHOLE_DNS_2}"
                fi

                # Dialog for the user to enter custom upstream servers
                piholeDNS=$(whiptail --backtitle "Specify Upstream DNS Provider(s)"  --inputbox "Enter your desired upstream DNS provider(s), separated by a comma.\\n\\nFor example '8.8.8.8, 8.8.4.4'" ${r} ${c} "${prePopulate}" 3>&1 1>&2 2>&3) || \
                { printf "  %bCancel was selected, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }
                # Clean user input and replace whitespace with comma.
                piholeDNS=$(sed 's/[, \t]\+/,/g' <<< "${piholeDNS}")

                printf -v PIHOLE_DNS_1 "%s" "${piholeDNS%%,*}"
                printf -v PIHOLE_DNS_2 "%s" "${piholeDNS##*,}"

                # If the IP is valid,
                if ! valid_ip "${PIHOLE_DNS_1}" || [[ ! "${PIHOLE_DNS_1}" ]]; then
                    # store it in the variable so we can use it
                    PIHOLE_DNS_1=${strInvalid}
                fi
                # Do the same for the secondary server
                if ! valid_ip "${PIHOLE_DNS_2}" && [[ "${PIHOLE_DNS_2}" ]]; then
                    PIHOLE_DNS_2=${strInvalid}
                fi
                # If either of the DNS servers are invalid,
                if [[ "${PIHOLE_DNS_1}" == "${strInvalid}" ]] || [[ "${PIHOLE_DNS_2}" == "${strInvalid}" ]]; then
                    # explain this to the user
                    whiptail --msgbox --backtitle "Invalid IP" --title "Invalid IP" "One or both entered IP addresses were invalid. Please try again.\\n\\n    DNS Server 1:   $PIHOLE_DNS_1\\n    DNS Server 2:   ${PIHOLE_DNS_2}" ${r} ${c}
                    # and set the variables back to nothing
                    if [[ "${PIHOLE_DNS_1}" == "${strInvalid}" ]]; then
                        PIHOLE_DNS_1=""
                    fi
                    if [[ "${PIHOLE_DNS_2}" == "${strInvalid}" ]]; then
                        PIHOLE_DNS_2=""
                    fi
                # Since the settings will not work, stay in the loop
                DNSSettingsCorrect=False
                # Otherwise,
                else
                    # Show the settings
                    if (whiptail --backtitle "Specify Upstream DNS Provider(s)" --title "Upstream DNS Provider(s)" --yesno "Are these settings correct?\\n    DNS Server 1:   $PIHOLE_DNS_1\\n    DNS Server 2:   ${PIHOLE_DNS_2}" ${r} ${c}); then
                    # and break from the loop since the servers are valid
                    DNSSettingsCorrect=True
                    # Otherwise,
                    else
                        # If the settings are wrong, the loop continues
                        DNSSettingsCorrect=False
                    fi
                fi
            done
            ;;
    esac
}

# Allow the user to enable/disable logging
setLogging() {
    # Local, named variables
    local LogToggleCommand
    local LogChooseOptions
    local LogChoices

    # Ask if the user wants to log queries
    LogToggleCommand=(whiptail --separate-output --radiolist "Do you want to log queries?" "${r}" "${c}" 6)
    # The default selection is on
    LogChooseOptions=("On (Recommended)" "" on
        Off "" off)
    # Get the user's choice
    LogChoices=$("${LogToggleCommand[@]}" "${LogChooseOptions[@]}" 2>&1 >/dev/tty) || (printf "  %bCancel was selected, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}" && exit 1)
    case ${LogChoices} in
        # If it's on
        "On (Recommended)")
            printf "  %b Logging On.\\n" "${INFO}"
            # Set the GLOBAL variable to true so we know what they selected
            QUERY_LOGGING=true
            ;;
        # Otherwise, it's off,
        Off)
            printf "  %b Logging Off.\\n" "${INFO}"
            # So set it to false
            QUERY_LOGGING=false
            ;;
    esac
}

# Allow the user to set their FTL privacy level
setPrivacyLevel() {
    local LevelCommand
    local LevelOptions

    LevelCommand=(whiptail --separate-output --radiolist "Select a privacy mode for FTL." "${r}" "${c}" 6)

    # The default selection is level 0
    LevelOptions=(
        "0" "Show everything" on
        "1" "Hide domains" off
        "2" "Hide domains and clients" off
        "3" "Anonymous mode" off
        "4" "Disabled statistics" off
    )

    # Get the user's choice
    PRIVACY_LEVEL=$("${LevelCommand[@]}" "${LevelOptions[@]}" 2>&1 >/dev/tty) || (echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}" && exit 1)

    printf "  %b Privacy level %d" "${INFO}" "${PRIVACY_LEVEL}"
}

# Function to ask the user if they want to install the dashboard
setAdminFlag() {
    # Local, named variables
    local WebToggleCommand
    local WebChooseOptions
    local WebChoices

    # Similar to the logging function, ask what the user wants
    WebToggleCommand=(whiptail --separate-output --radiolist "Do you wish to install the web admin interface?" ${r} ${c} 6)
    # with the default being enabled
    WebChooseOptions=("On (Recommended)" "" on
        Off "" off)
    WebChoices=$("${WebToggleCommand[@]}" "${WebChooseOptions[@]}" 2>&1 >/dev/tty) || (printf "  %bCancel was selected, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}" && exit 1)
    # Depending on their choice
    case ${WebChoices} in
        "On (Recommended)")
            printf "  %b Web Interface On\\n" "${INFO}"
            # Set it to true
            INSTALL_WEB_INTERFACE=true
            ;;
        Off)
            printf "  %b Web Interface Off\\n" "${INFO}"
            # or false
            INSTALL_WEB_INTERFACE=false
            ;;
    esac

    # Request user to install web server, if --disable-install-webserver has not been used (INSTALL_WEB_SERVER=true is default).
    if [[ "${INSTALL_WEB_SERVER}" == true ]]; then
        WebToggleCommand=(whiptail --separate-output --radiolist "Do you wish to install the web server (lighttpd)?\\n\\nNB: If you disable this, and, do not have an existing webserver installed, the web interface will not function." "${r}" "${c}" 6)
        # with the default being enabled
        WebChooseOptions=("On (Recommended)" "" on
            Off "" off)
        WebChoices=$("${WebToggleCommand[@]}" "${WebChooseOptions[@]}" 2>&1 >/dev/tty) || (printf "  %bCancel was selected, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}" && exit 1)
        # Depending on their choice
        case ${WebChoices} in
            "On (Recommended)")
                printf "  %b Web Server On\\n" "${INFO}"
                # set it to true, as clearly seen below.
                INSTALL_WEB_SERVER=true
                ;;
            Off)
                printf "  %b Web Server Off\\n" "${INFO}"
                # or false
                INSTALL_WEB_SERVER=false
                ;;
        esac
    fi
}

# A function to display a list of example blocklists for users to select
chooseBlocklists() {
    # Back up any existing adlist file, on the off chance that it exists. Useful in case of a reconfigure.
    if [[ -f "${adlistFile}" ]]; then
        mv "${adlistFile}" "${adlistFile}.old"
    fi
    # Let user select (or not) blocklists via a checklist
    cmd=(whiptail --separate-output --checklist "Pi-hole relies on third party lists in order to block ads.\\n\\nYou can use the suggestions below, and/or add your own after installation\\n\\nTo deselect any list, use the arrow keys and spacebar" "${r}" "${c}" 7)
    # In an array, show the options available (all off by default):
    options=(StevenBlack "StevenBlack's Unified Hosts List" on
        MalwareDom "MalwareDomains" on
        Cameleon "Cameleon" on
        ZeusTracker "ZeusTracker" on
        DisconTrack "Disconnect.me Tracking" on
        DisconAd "Disconnect.me Ads" on
        HostsFile "Hosts-file.net Ads" on)

    # In a variable, show the choices available; exit if Cancel is selected
    choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty) || { printf "  %bCancel was selected, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; rm "${adlistFile}" ;exit 1; }
    # For each choice available,
    for choice in ${choices}
    do
        appendToListsFile "${choice}"
    done
}

# Accept a string parameter, it must be one of the default lists
# This function allow to not duplicate code in chooseBlocklists and
# in installDefaultBlocklists
appendToListsFile() {
    case $1 in
        StevenBlack  )  echo "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" >> "${adlistFile}";;
        MalwareDom   )  echo "https://mirror1.malwaredomains.com/files/justdomains" >> "${adlistFile}";;
        Cameleon     )  echo "http://sysctl.org/cameleon/hosts" >> "${adlistFile}";;
        ZeusTracker  )  echo "https://zeustracker.abuse.ch/blocklist.php?download=domainblocklist" >> "${adlistFile}";;
        DisconTrack  )  echo "https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt" >> "${adlistFile}";;
        DisconAd     )  echo "https://s3.amazonaws.com/lists.disconnect.me/simple_ad.txt" >> "${adlistFile}";;
        HostsFile    )  echo "https://hosts-file.net/ad_servers.txt" >> "${adlistFile}";;
    esac
}

# Used only in unattended setup
# If there is already the adListFile, we keep it, else we create it using all default lists
installDefaultBlocklists() {
    # In unattended setup, could be useful to use userdefined blocklist.
    # If this file exists, we avoid overriding it.
    if [[ -f "${adlistFile}" ]]; then
        return;
    fi
    appendToListsFile StevenBlack
    appendToListsFile MalwareDom
    appendToListsFile Cameleon
    appendToListsFile ZeusTracker
    appendToListsFile DisconTrack
    appendToListsFile DisconAd
    appendToListsFile HostsFile
}

# Check if /etc/dnsmasq.conf is from pi-hole.  If so replace with an original and install new in .d directory
version_check_dnsmasq() {
    # Local, named variables
    local dnsmasq_conf="/etc/dnsmasq.conf"
    local dnsmasq_conf_orig="/etc/dnsmasq.conf.orig"
    local dnsmasq_pihole_id_string="addn-hosts=/etc/pihole/gravity.list"
    local dnsmasq_original_config="${PI_HOLE_LOCAL_REPO}/advanced/dnsmasq.conf.original"
    local dnsmasq_pihole_01_snippet="${PI_HOLE_LOCAL_REPO}/advanced/01-pihole.conf"
    local dnsmasq_pihole_01_location="/etc/dnsmasq.d/01-pihole.conf"

    # If the dnsmasq config file exists
    if [[ -f "${dnsmasq_conf}" ]]; then
        printf "  %b Existing dnsmasq.conf found..." "${INFO}"
        # If gravity.list is found within this file, we presume it's from older versions on Pi-hole,
        if grep -q ${dnsmasq_pihole_id_string} ${dnsmasq_conf}; then
            printf " it is from a previous Pi-hole install.\\n"
            printf "  %b Backing up dnsmasq.conf to dnsmasq.conf.orig..." "${INFO}"
            # so backup the original file
            mv -f ${dnsmasq_conf} ${dnsmasq_conf_orig}
            printf "%b  %b Backing up dnsmasq.conf to dnsmasq.conf.orig...\\n" "${OVER}"  "${TICK}"
            printf "  %b Restoring default dnsmasq.conf..." "${INFO}"
            # and replace it with the default
            cp ${dnsmasq_original_config} ${dnsmasq_conf}
            printf "%b  %b Restoring default dnsmasq.conf...\\n" "${OVER}"  "${TICK}"
        # Otherwise,
        else
        # Don't to anything
        printf " it is not a Pi-hole file, leaving alone!\\n"
        fi
    else
        # If a file cannot be found,
        printf "  %b No dnsmasq.conf found... restoring default dnsmasq.conf..." "${INFO}"
        # restore the default one
        cp ${dnsmasq_original_config} ${dnsmasq_conf}
        printf "%b  %b No dnsmasq.conf found... restoring default dnsmasq.conf...\\n" "${OVER}"  "${TICK}"
    fi

    printf "  %b Copying 01-pihole.conf to /etc/dnsmasq.d/01-pihole.conf..." "${INFO}"
    # Check to see if dnsmasq directory exists (it may not due to being a fresh install and dnsmasq no longer being a dependency)
    if [[ ! -d "/etc/dnsmasq.d"  ]];then
        mkdir "/etc/dnsmasq.d"
    fi
    # Copy the new Pi-hole DNS config file into the dnsmasq.d directory
    cp ${dnsmasq_pihole_01_snippet} ${dnsmasq_pihole_01_location}
    printf "%b  %b Copying 01-pihole.conf to /etc/dnsmasq.d/01-pihole.conf\\n" "${OVER}"  "${TICK}"
    # Replace our placeholder values with the GLOBAL DNS variables that we populated earlier
    # First, swap in the interface to listen on
    sed -i "s/@INT@/$PIHOLE_INTERFACE/" ${dnsmasq_pihole_01_location}
    if [[ "${PIHOLE_DNS_1}" != "" ]]; then
        # Then swap in the primary DNS server
        sed -i "s/@DNS1@/$PIHOLE_DNS_1/" ${dnsmasq_pihole_01_location}
    else
        #
        sed -i '/^server=@DNS1@/d' ${dnsmasq_pihole_01_location}
    fi
    if [[ "${PIHOLE_DNS_2}" != "" ]]; then
        # Then swap in the primary DNS server
        sed -i "s/@DNS2@/$PIHOLE_DNS_2/" ${dnsmasq_pihole_01_location}
    else
        #
        sed -i '/^server=@DNS2@/d' ${dnsmasq_pihole_01_location}
    fi

    #
    sed -i 's/^#conf-dir=\/etc\/dnsmasq.d$/conf-dir=\/etc\/dnsmasq.d/' ${dnsmasq_conf}

    # If the user does not want to enable logging,
    if [[ "${QUERY_LOGGING}" == false ]] ; then
        # Disable it by commenting out the directive in the DNS config file
        sed -i 's/^log-queries/#log-queries/' ${dnsmasq_pihole_01_location}
    # Otherwise,
    else
        # enable it by uncommenting the directive in the DNS config file
        sed -i 's/^#log-queries/log-queries/' ${dnsmasq_pihole_01_location}
    fi
}

# Clean an existing installation to prepare for upgrade/reinstall
clean_existing() {
    # Local, named variables
    # ${1} Directory to clean
    local clean_directory="${1}"
    # Make ${2} the new one?
    shift
    # ${2} Array of files to remove
    local old_files=( "$@" )

    # For each script found in the old files array
    for script in "${old_files[@]}"; do
        # Remove them
        rm -f "${clean_directory}/${script}.sh"
    done
}

# Install the scripts from repository to their various locations
installScripts() {
    # Local, named variables
    local str="Installing scripts from ${PI_HOLE_LOCAL_REPO}"
    printf "  %b %s..." "${INFO}" "${str}"

    # Clear out script files from Pi-hole scripts directory.
    clean_existing "${PI_HOLE_INSTALL_DIR}" "${PI_HOLE_FILES[@]}"

    # Install files from local core repository
    if is_repo "${PI_HOLE_LOCAL_REPO}"; then
        # move into the directory
        cd "${PI_HOLE_LOCAL_REPO}"
        # Install the scripts by:
        #  -o setting the owner to the user
        #  -Dm755 create all leading components of destination except the last, then copy the source to the destination and setting the permissions to 755
        #
        # This first one is the directory
        install -o "${USER}" -Dm755 -d "${PI_HOLE_INSTALL_DIR}"
        # The rest are the scripts Pi-hole needs
        install -o "${USER}" -Dm755 -t "${PI_HOLE_INSTALL_DIR}" gravity.sh
        install -o "${USER}" -Dm755 -t "${PI_HOLE_INSTALL_DIR}" ./advanced/Scripts/*.sh
        install -o "${USER}" -Dm755 -t "${PI_HOLE_INSTALL_DIR}" ./automated\ install/uninstall.sh
        install -o "${USER}" -Dm755 -t "${PI_HOLE_INSTALL_DIR}" ./advanced/Scripts/COL_TABLE
        install -o "${USER}" -Dm755 -t /usr/local/bin/ pihole
        install -Dm644 ./advanced/bash-completion/pihole /etc/bash_completion.d/pihole
        printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"

    # Otherwise,
    else
        # Show an error and exit
        printf "%b  %b %s\\n" "${OVER}"  "${CROSS}" "${str}"
        printf "\\t\\t%bError: Local repo %s not found, exiting installer%b\\n" "${COL_LIGHT_RED}" "${PI_HOLE_LOCAL_REPO}" "${COL_NC}"
        return 1
    fi
}

# Install the configs from PI_HOLE_LOCAL_REPO to their various locations
installConfigs() {
    printf "\\n  %b Installing configs from %s...\\n" "${INFO}" "${PI_HOLE_LOCAL_REPO}"
    # Make sure Pi-hole's config files are in place
    version_check_dnsmasq
    # Install empty file if it does not exist
    if [[ ! -f "${PI_HOLE_CONFIG_DIR}/pihole-FTL.conf" ]]; then
        if ! install -o pihole -g pihole -m 664 /dev/null "${PI_HOLE_CONFIG_DIR}/pihole-FTL.conf" &>/dev/null; then
            printf "  %bError: Unable to initialize configuration file %s/pihole-FTL.conf\\n" "${COL_LIGHT_RED}" "${PI_HOLE_CONFIG_DIR}"
            return 1
        fi
    fi
    # Install an empty regex file
    if [[ ! -f "${regexFile}" ]]; then
        # Let PHP edit the regex file, if installed
        install -o pihole -g "${LIGHTTPD_GROUP:-pihole}" -m 664 /dev/null "${regexFile}"
    fi
    # If the user chose to install the dashboard,
    if [[ "${INSTALL_WEB_SERVER}" == true ]]; then
        # and if the Web server conf directory does not exist,
        if [[ ! -d "/etc/lighttpd" ]]; then
            # make it
            mkdir /etc/lighttpd
            # and set the owners
            chown "${USER}":root /etc/lighttpd
        # Otherwise, if the config file already exists
        elif [[ -f "/etc/lighttpd/lighttpd.conf" ]]; then
            # back up the original
            mv /etc/lighttpd/lighttpd.conf /etc/lighttpd/lighttpd.conf.orig
        fi
        # and copy in the config file Pi-hole needs
        cp ${PI_HOLE_LOCAL_REPO}/advanced/${LIGHTTPD_CFG} /etc/lighttpd/lighttpd.conf
        # Make sure the external.conf file exists, as lighttpd v1.4.50 crashes without it
        touch /etc/lighttpd/external.conf
        # if there is a custom block page in the html/pihole directory, replace 404 handler in lighttpd config
        if [[ -f "/var/www/html/pihole/custom.php" ]]; then
            sed -i 's/^\(server\.error-handler-404\s*=\s*\).*$/\1"pihole\/custom\.php"/' /etc/lighttpd/lighttpd.conf
        fi
        # Make the directories if they do not exist and set the owners
        mkdir -p /var/run/lighttpd
        chown ${LIGHTTPD_USER}:${LIGHTTPD_GROUP} /var/run/lighttpd
        mkdir -p /var/cache/lighttpd/compress
        chown ${LIGHTTPD_USER}:${LIGHTTPD_GROUP} /var/cache/lighttpd/compress
        mkdir -p /var/cache/lighttpd/uploads
        chown ${LIGHTTPD_USER}:${LIGHTTPD_GROUP} /var/cache/lighttpd/uploads
    fi
}

install_manpage() {
    # Copy Pi-hole man pages and call mandb to update man page database
    # Default location for man files for /usr/local/bin is /usr/local/share/man
    # on lightweight systems may not be present, so check before copying.
    printf "  %b Testing man page installation" "${INFO}"
    if ! is_command mandb ; then
        # if mandb is not present, no manpage support
        printf "%b  %b man not installed\\n" "${OVER}" "${INFO}"
        return
    elif [[ ! -d "/usr/local/share/man" ]]; then
        # appropriate directory for Pi-hole's man page is not present
        printf "%b  %b man pages not installed\\n" "${OVER}" "${INFO}"
        return
    fi
    if [[ ! -d "/usr/local/share/man/man8" ]]; then
        # if not present, create man8 directory
        mkdir /usr/local/share/man/man8
    fi
    if [[ ! -d "/usr/local/share/man/man5" ]]; then
        # if not present, create man8 directory
        mkdir /usr/local/share/man/man5
    fi
    # Testing complete, copy the files & update the man db
    cp ${PI_HOLE_LOCAL_REPO}/manpages/pihole.8 /usr/local/share/man/man8/pihole.8
    cp ${PI_HOLE_LOCAL_REPO}/manpages/pihole-FTL.8 /usr/local/share/man/man8/pihole-FTL.8
    cp ${PI_HOLE_LOCAL_REPO}/manpages/pihole-FTL.conf.5 /usr/local/share/man/man5/pihole-FTL.conf.5
    if mandb -q &>/dev/null; then
        # Updated successfully
        printf "%b  %b man pages installed and database updated\\n" "${OVER}" "${TICK}"
        return
    else
        # Something is wrong with the system's man installation, clean up
        # our files, (leave everything how we found it).
        rm /usr/local/share/man/man8/pihole.8 /usr/local/share/man/man8/pihole-FTL.8 /usr/local/share/man/man5/pihole-FTL.conf.5
        printf "%b  %b man page db not updated, man pages not installed\\n" "${OVER}" "${CROSS}"
    fi
}

stop_service() {
    # Stop service passed in as argument.
    # Can softfail, as process may not be installed when this is called
    local str="Stopping ${1} service"
    printf "  %b %s..." "${INFO}" "${str}"
    if is_command systemctl ; then
        systemctl stop "${1}" &> /dev/null || true
    else
        service "${1}" stop &> /dev/null || true
    fi
    printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
}

# Start/Restart service passed in as argument
restart_service() {
    # Local, named variables
    local str="Restarting ${1} service"
    printf "  %b %s..." "${INFO}" "${str}"
    # If systemctl exists,
    if is_command systemctl ; then
        # use that to restart the service
        systemctl restart "${1}" &> /dev/null
    # Otherwise,
    else
        # fall back to the service command
        service "${1}" restart &> /dev/null
    fi
    printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
}

# Enable service so that it will start with next reboot
enable_service() {
    # Local, named variables
    local str="Enabling ${1} service to start on reboot"
    printf "  %b %s..." "${INFO}" "${str}"
    # If systemctl exists,
    if is_command systemctl ; then
        # use that to enable the service
        systemctl enable "${1}" &> /dev/null
    # Otherwise,
    else
        # use update-rc.d to accomplish this
        update-rc.d "${1}" defaults &> /dev/null
    fi
    printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
}

# Disable service so that it will not with next reboot
disable_service() {
    # Local, named variables
    local str="Disabling ${1} service"
    printf "  %b %s..." "${INFO}" "${str}"
    # If systemctl exists,
    if is_command systemctl ; then
        # use that to disable the service
        systemctl disable "${1}" &> /dev/null
    # Otherwise,
    else
        # use update-rc.d to accomplish this
        update-rc.d "${1}" disable &> /dev/null
    fi
    printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
}

check_service_active() {
    # If systemctl exists,
    if is_command systemctl ; then
        # use that to check the status of the service
        systemctl is-enabled "${1}" &> /dev/null
    # Otherwise,
    else
        # fall back to service command
        service "${1}" status &> /dev/null
    fi
}

# Systemd-resolved's DNSStubListener and dnsmasq can't share port 53.
disable_resolved_stublistener() {
    printf "  %b Testing if systemd-resolved is enabled\\n" "${INFO}"
    # Check if Systemd-resolved's DNSStubListener is enabled and active on port 53
    if check_service_active "systemd-resolved"; then
        # Check if DNSStubListener is enabled
        printf "  %b  %b Testing if systemd-resolved DNSStub-Listener is active" "${OVER}" "${INFO}"
        if ( grep -E '#?DNSStubListener=yes' /etc/systemd/resolved.conf &> /dev/null ); then
            # Disable the DNSStubListener to unbind it from port 53
            # Note that this breaks dns functionality on host until dnsmasq/ftl are up and running
            printf "%b  %b Disabling systemd-resolved DNSStubListener" "${OVER}" "${TICK}"
            # Make a backup of the original /etc/systemd/resolved.conf
            # (This will need to be restored on uninstallation)
            sed -r -i.orig 's/#?DNSStubListener=yes/DNSStubListener=no/g' /etc/systemd/resolved.conf
            printf " and restarting systemd-resolved\\n"
            systemctl reload-or-restart systemd-resolved
        else
            printf "%b  %b Systemd-resolved does not need to be restarted\\n" "${OVER}" "${INFO}"
        fi
    else
        printf "%b  %b Systemd-resolved is not enabled\\n" "${OVER}" "${INFO}"
    fi
}

update_package_cache() {
    # Running apt-get update/upgrade with minimal output can cause some issues with
    # requiring user input (e.g password for phpmyadmin see #218)

    # Update package cache on apt based OSes. Do this every time since
    # it's quick and packages can be updated at any time.

    # Local, named variables
    local str="Update local cache of available packages"
    printf "  %b %s..." "${INFO}" "${str}"
    # Create a command from the package cache variable
    if eval "${UPDATE_PKG_CACHE}" &> /dev/null; then
        printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
    # Otherwise,
    else
        # show an error and exit
        printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
        printf "  %bError: Unable to update package cache. Please try \"%s\"%b" "${COL_LIGHT_RED}" "${COL_LIGHT_RED}" "${COL_NC}"
        return 1
    fi
}

# Let user know if they have outdated packages on their system and
# advise them to run a package update at soonest possible.
notify_package_updates_available() {
    # Local, named variables
    local str="Checking ${PKG_MANAGER} for upgraded packages"
    printf "\\n  %b %s..." "${INFO}" "${str}"
    # Store the list of packages in a variable
    updatesToInstall=$(eval "${PKG_COUNT}")

    if [[ -d "/lib/modules/$(uname -r)" ]]; then
        if [[ "${updatesToInstall}" -eq 0 ]]; then
            printf "%b  %b %s... up to date!\\n\\n" "${OVER}" "${TICK}" "${str}"
        else
            printf "%b  %b %s... %s updates available\\n" "${OVER}" "${TICK}" "${str}" "${updatesToInstall}"
            printf "  %b %bIt is recommended to update your OS after installing the Pi-hole!%b\\n\\n" "${INFO}" "${COL_LIGHT_GREEN}" "${COL_NC}"
        fi
    else
        printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
        printf "      Kernel update detected. If the install fails, please reboot and try again\\n"
    fi
}

# What's this doing outside of a function in the middle of nowhere?
counter=0

install_dependent_packages() {
    # Local, named variables should be used here, especially for an iterator
    # Add one to the counter
    counter=$((counter+1))
    # If it equals 1,
    if [[ "${counter}" == 1 ]]; then
        #
        printf "  %b Installer Dependency checks...\\n" "${INFO}"
    else
        #
        printf "  %b Main Dependency checks...\\n" "${INFO}"
    fi

    # Install packages passed in via argument array
    # No spinner - conflicts with set -e
    declare -a argArray1=("${!1}")
    declare -a installArray

    # Debian based package install - debconf will download the entire package list
    # so we just create an array of packages not currently installed to cut down on the
    # amount of download traffic.
    # NOTE: We may be able to use this installArray in the future to create a list of package that were
    # installed by us, and remove only the installed packages, and not the entire list.
    if is_command debconf-apt-progress ; then
        # For each package,
        for i in "${argArray1[@]}"; do
            printf "  %b Checking for %s..." "${INFO}" "${i}"
            if dpkg-query -W -f='${Status}' "${i}" 2>/dev/null | grep "ok installed" &> /dev/null; then
                printf "%b  %b Checking for %s\\n" "${OVER}" "${TICK}" "${i}"
            else
                echo -e "${OVER}  ${INFO} Checking for $i (will be installed)"
                installArray+=("${i}")
            fi
        done
        if [[ "${#installArray[@]}" -gt 0 ]]; then
            test_dpkg_lock
            debconf-apt-progress -- "${PKG_INSTALL[@]}" "${installArray[@]}"
            return
        fi
        printf "\\n"
        return 0
    fi

    # Install Fedora/CentOS packages
    for i in "${argArray1[@]}"; do
        printf "  %b Checking for %s..." "${INFO}" "${i}"
        if ${PKG_MANAGER} -q list installed "${i}" &> /dev/null; then
            printf "%b  %b Checking for %s" "${OVER}" "${TICK}" "${i}"
        else
            printf "%b  %b Checking for %s (will be installed)" "${OVER}" "${INFO}" "${i}"
            installArray+=("${i}")
        fi
    done
    if [[ "${#installArray[@]}" -gt 0 ]]; then
        "${PKG_INSTALL[@]}" "${installArray[@]}" &> /dev/null
        return
    fi
    printf "\\n"
    return 0
}

# Install the Web interface dashboard
installPiholeWeb() {
    printf "\\n  %b Installing blocking page...\\n" "${INFO}"

    local str="Creating directory for blocking page, and copying files"
    printf "  %b %s..." "${INFO}" "${str}"
    # Install the directory
    install -d /var/www/html/pihole
    # and the blockpage
    install -D ${PI_HOLE_LOCAL_REPO}/advanced/{index,blockingpage}.* /var/www/html/pihole/

    # Remove superseded file
    if [[ -e "/var/www/html/pihole/index.js" ]]; then
        rm "/var/www/html/pihole/index.js"
    fi

    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"

    local str="Backing up index.lighttpd.html"
    printf "  %b %s..." "${INFO}" "${str}"
    # If the default index file exists,
    if [[ -f "/var/www/html/index.lighttpd.html" ]]; then
        # back it up
        mv /var/www/html/index.lighttpd.html /var/www/html/index.lighttpd.orig
        printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
    # Otherwise,
    else
        # don't do anything
        printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
        printf "      No default index.lighttpd.html file found... not backing up\\n"
    fi

    # Install Sudoers file
    local str="Installing sudoer file"
    printf "\\n  %b %s..." "${INFO}" "${str}"
    # Make the .d directory if it doesn't exist
    mkdir -p /etc/sudoers.d/
    # and copy in the pihole sudoers file
    cp ${PI_HOLE_LOCAL_REPO}/advanced/Templates/pihole.sudo /etc/sudoers.d/pihole
    # Add lighttpd user (OS dependent) to sudoers file
    echo "${LIGHTTPD_USER} ALL=NOPASSWD: /usr/local/bin/pihole" >> /etc/sudoers.d/pihole

    # If the Web server user is lighttpd,
    if [[ "$LIGHTTPD_USER" == "lighttpd" ]]; then
        # Allow executing pihole via sudo with Fedora
        # Usually /usr/local/bin is not permitted as directory for sudoable programs
        echo "Defaults secure_path = /sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin" >> /etc/sudoers.d/pihole
    fi
    # Set the strict permissions on the file
    chmod 0440 /etc/sudoers.d/pihole
    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
}

# Installs a cron file
installCron() {
    # Install the cron job
    local str="Installing latest Cron script"
    printf "\\n  %b %s..." "${INFO}" "${str}"
    # Copy the cron file over from the local repo
    cp ${PI_HOLE_LOCAL_REPO}/advanced/Templates/pihole.cron /etc/cron.d/pihole
    # Randomize gravity update time
    sed -i "s/59 1 /$((1 + RANDOM % 58)) $((3 + RANDOM % 2))/" /etc/cron.d/pihole
    # Randomize update checker time
    sed -i "s/59 17/$((1 + RANDOM % 58)) $((12 + RANDOM % 8))/" /etc/cron.d/pihole
    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
}

# Gravity is a very important script as it aggregates all of the domains into a single HOSTS formatted list,
# which is what Pi-hole needs to begin blocking ads
runGravity() {
    # Run gravity in the current shell
    { /opt/pihole/gravity.sh --force; }
}

# Check if the pihole user exists and create if it does not
create_pihole_user() {
    local str="Checking for user 'pihole'"
    printf "  %b %s..." "${INFO}" "${str}"
    # If the user pihole exists,
    if id -u pihole &> /dev/null; then
        # just show a success
        printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
    # Otherwise,
    else
        printf "%b  %b %s" "${OVER}" "${CROSS}" "${str}"
        local str="Creating user 'pihole'"
        printf "%b  %b %s..." "${OVER}" "${INFO}" "${str}"
        # create her with the useradd command
        if useradd -r -s /usr/sbin/nologin pihole; then
          printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
        else
          printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
        fi
    fi
}

# Allow HTTP and DNS traffic
configureFirewall() {
    printf "\\n"
    # If a firewall is running,
    if firewall-cmd --state &> /dev/null; then
        # ask if the user wants to install Pi-hole's default firewall rules
        whiptail --title "Firewall in use" --yesno "We have detected a running firewall\\n\\nPi-hole currently requires HTTP and DNS port access.\\n\\n\\n\\nInstall Pi-hole default firewall rules?" ${r} ${c} || \
        { printf "  %b Not installing firewall rulesets.\\n" "${INFO}"; return 0; }
        printf "  %b Configuring FirewallD for httpd and pihole-FTL\\n" "${TICK}"
        # Allow HTTP and DNS traffic
        firewall-cmd --permanent --add-service=http --add-service=dns
        # Reload the firewall to apply these changes
        firewall-cmd --reload
        return 0
        # Check for proper kernel modules to prevent failure
    elif modinfo ip_tables &> /dev/null && is_command iptables ; then
    # If chain Policy is not ACCEPT or last Rule is not ACCEPT
    # then check and insert our Rules above the DROP/REJECT Rule.
        if iptables -S INPUT | head -n1 | grep -qv '^-P.*ACCEPT$' || iptables -S INPUT | tail -n1 | grep -qv '^-\(A\|P\).*ACCEPT$'; then
            whiptail --title "Firewall in use" --yesno "We have detected a running firewall\\n\\nPi-hole currently requires HTTP and DNS port access.\\n\\n\\n\\nInstall Pi-hole default firewall rules?" ${r} ${c} || \
            { printf "  %b Not installing firewall rulesets.\\n" "${INFO}"; return 0; }
            printf "  %b Installing new IPTables firewall rulesets\\n" "${TICK}"
            # Check chain first, otherwise a new rule will duplicate old ones
            iptables -C INPUT -p tcp -m tcp --dport 80 -j ACCEPT &> /dev/null || iptables -I INPUT 1 -p tcp -m tcp --dport 80 -j ACCEPT
            iptables -C INPUT -p tcp -m tcp --dport 53 -j ACCEPT &> /dev/null || iptables -I INPUT 1 -p tcp -m tcp --dport 53 -j ACCEPT
            iptables -C INPUT -p udp -m udp --dport 53 -j ACCEPT &> /dev/null || iptables -I INPUT 1 -p udp -m udp --dport 53 -j ACCEPT
            iptables -C INPUT -p tcp -m tcp --dport 4711:4720 -i lo -j ACCEPT &> /dev/null || iptables -I INPUT 1 -p tcp -m tcp --dport 4711:4720 -i lo -j ACCEPT
            return 0
        fi
    # Otherwise,
    else
        # no firewall is running
        printf "  %b No active firewall detected.. skipping firewall configuration\\n" "${INFO}"
        # so just exit
        return 0
    fi
    printf "  %b Skipping firewall configuration\\n" "${INFO}"
}

#
finalExports() {
    # If the Web interface is not set to be installed,
    if [[ "${INSTALL_WEB_INTERFACE}" == false ]]; then
        # and if there is not an IPv4 address,
        if [[ "${IPV4_ADDRESS}" ]]; then
            # there is no block page, so set IPv4 to 0.0.0.0 (all IP addresses)
            IPV4_ADDRESS="0.0.0.0"
        fi
        if [[ "${IPV6_ADDRESS}" ]]; then
            # and IPv6 to ::/0
            IPV6_ADDRESS="::/0"
        fi
    fi

    # If the setup variable file exists,
    if [[ -e "${setupVars}" ]]; then
        # update the variables in the file
        sed -i.update.bak '/PIHOLE_INTERFACE/d;/IPV4_ADDRESS/d;/IPV6_ADDRESS/d;/PIHOLE_DNS_1/d;/PIHOLE_DNS_2/d;/QUERY_LOGGING/d;/INSTALL_WEB_SERVER/d;/INSTALL_WEB_INTERFACE/d;/LIGHTTPD_ENABLED/d;' "${setupVars}"
    fi
    # echo the information to the user
    {
    echo "PIHOLE_INTERFACE=${PIHOLE_INTERFACE}"
    echo "IPV4_ADDRESS=${IPV4_ADDRESS}"
    echo "IPV6_ADDRESS=${IPV6_ADDRESS}"
    echo "PIHOLE_DNS_1=${PIHOLE_DNS_1}"
    echo "PIHOLE_DNS_2=${PIHOLE_DNS_2}"
    echo "QUERY_LOGGING=${QUERY_LOGGING}"
    echo "INSTALL_WEB_SERVER=${INSTALL_WEB_SERVER}"
    echo "INSTALL_WEB_INTERFACE=${INSTALL_WEB_INTERFACE}"
    echo "LIGHTTPD_ENABLED=${LIGHTTPD_ENABLED}"
    }>> "${setupVars}"

    # Set the privacy level
    sed -i '/PRIVACYLEVEL/d' "${PI_HOLE_CONFIG_DIR}/pihole-FTL.conf"
    echo "PRIVACYLEVEL=${PRIVACY_LEVEL}" >> "${PI_HOLE_CONFIG_DIR}/pihole-FTL.conf"

    # Bring in the current settings and the functions to manipulate them
    source "${setupVars}"
    source "${PI_HOLE_LOCAL_REPO}/advanced/Scripts/webpage.sh"

    # Look for DNS server settings which would have to be reapplied
    ProcessDNSSettings

    # Look for DHCP server settings which would have to be reapplied
    ProcessDHCPSettings
}

# Install the logrotate script
installLogrotate() {

    local str="Installing latest logrotate script"
    printf "\\n  %b %s..." "${INFO}" "${str}"
    # Copy the file over from the local repo
    cp ${PI_HOLE_LOCAL_REPO}/advanced/Templates/logrotate /etc/pihole/logrotate
    # Different operating systems have different user / group
    # settings for logrotate that makes it impossible to create
    # a static logrotate file that will work with e.g.
    # Rasbian and Ubuntu at the same time. Hence, we have to
    # customize the logrotate script here in order to reflect
    # the local properties of the /var/log directory
    logusergroup="$(stat -c '%U %G' /var/log)"
    # If the variable has a value,
    if [[ ! -z "${logusergroup}" ]]; then
        #
        sed -i "s/# su #/su ${logusergroup}/g;" /etc/pihole/logrotate
    fi
    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
}

# At some point in the future this list can be pruned, for now we'll need it to ensure updates don't break.
# Refactoring of install script has changed the name of a couple of variables. Sort them out here.
accountForRefactor() {
    sed -i 's/piholeInterface/PIHOLE_INTERFACE/g' ${setupVars}
    sed -i 's/IPv4_address/IPV4_ADDRESS/g' ${setupVars}
    sed -i 's/IPv4addr/IPV4_ADDRESS/g' ${setupVars}
    sed -i 's/IPv6_address/IPV6_ADDRESS/g' ${setupVars}
    sed -i 's/piholeIPv6/IPV6_ADDRESS/g' ${setupVars}
    sed -i 's/piholeDNS1/PIHOLE_DNS_1/g' ${setupVars}
    sed -i 's/piholeDNS2/PIHOLE_DNS_2/g' ${setupVars}
    sed -i 's/^INSTALL_WEB=/INSTALL_WEB_INTERFACE=/' ${setupVars}
    # Add 'INSTALL_WEB_SERVER', if its not been applied already: https://github.com/pi-hole/pi-hole/pull/2115
    if ! grep -q '^INSTALL_WEB_SERVER=' ${setupVars}; then
        local webserver_installed=false
        if grep -q '^INSTALL_WEB_INTERFACE=true' ${setupVars}; then
            webserver_installed=true
        fi
        echo -e "INSTALL_WEB_SERVER=$webserver_installed" >> ${setupVars}
    fi
}

# Install base files and web interface
installPihole() {
    # Create the pihole user
    create_pihole_user

    # If the user wants to install the Web interface,
    if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then
        if [[ ! -d "/var/www/html" ]]; then
            # make the Web directory if necessary
            mkdir -p /var/www/html
        fi

        if [[ "${INSTALL_WEB_SERVER}" == true ]]; then
            # Set the owner and permissions
            chown ${LIGHTTPD_USER}:${LIGHTTPD_GROUP} /var/www/html
            chmod 775 /var/www/html
            # Give pihole access to the Web server group
            usermod -a -G ${LIGHTTPD_GROUP} pihole
            # If the lighttpd command is executable,
            if is_command lighty-enable-mod ; then
                # enable fastcgi and fastcgi-php
                lighty-enable-mod fastcgi fastcgi-php > /dev/null || true
            else
                # Otherwise, show info about installing them
                printf "  %b Warning: 'lighty-enable-mod' utility not found\\n" "${INFO}"
                printf "      Please ensure fastcgi is enabled if you experience issues\\n"
            fi
        fi
    fi
    # For updates and unattended install.
    if [[ "${useUpdateVars}" == true ]]; then
        accountForRefactor
    fi
    # Install base files and web interface
    if ! installScripts; then
        printf "  %b Failure in dependent script copy function.\\n" "${CROSS}"
        exit 1
    fi
    # Install config files
    if ! installConfigs; then
        printf "  %b Failure in dependent config copy function.\\n" "${CROSS}"
        exit 1
    fi
    # If the user wants to install the dashboard,
    if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then
        # do so
        installPiholeWeb
    fi
    # Install the cron file
    installCron
    # Install the logrotate file
    installLogrotate
    # Check if dnsmasq is present. If so, disable it and back up any possible
    # config file
    disable_dnsmasq
    # Configure the firewall
    if [[ "${useUpdateVars}" == false ]]; then
        configureFirewall
    fi

    # install a man page entry for pihole
    install_manpage

    # Update setupvars.conf with any variables that may or may not have been changed during the install
    finalExports
}

# SELinux
checkSelinux() {
    # If the getenforce command exists,
    if is_command getenforce ; then
        # Store the current mode in a variable
        enforceMode=$(getenforce)
        printf "\\n  %b SELinux mode detected: %s\\n" "${INFO}" "${enforceMode}"

        # If it's enforcing,
        if [[ "${enforceMode}" == "Enforcing" ]]; then
            # Explain Pi-hole does not support it yet
            whiptail --defaultno --title "SELinux Enforcing Detected" --yesno "SELinux is being ENFORCED on your system! \\n\\nPi-hole currently does not support SELinux, but you may still continue with the installation.\\n\\nNote: Web Admin will not be fully functional unless you set your policies correctly\\n\\nContinue installing Pi-hole?" ${r} ${c} || \
            { printf "\\n  %bSELinux Enforcing detected, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }
            printf "  %b Continuing installation with SELinux Enforcing\\n" "${INFO}"
            printf "      %b Please refer to official SELinux documentation to create a custom policy\\n" "${INFO}"
        fi
    fi
}

# Installation complete message with instructions for the user
displayFinalMessage() {
    # If
    if [[ "${#1}" -gt 0 ]] ; then
        pwstring="$1"
        # else, if the dashboard password in the setup variables exists,
    elif [[ $(grep 'WEBPASSWORD' -c /etc/pihole/setupVars.conf) -gt 0 ]]; then
        # set a variable for evaluation later
        pwstring="unchanged"
    else
        # set a variable for evaluation later
        pwstring="NOT SET"
    fi
    # If the user wants to install the dashboard,
    if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then
        # Store a message in a variable and display it
        additional="View the web interface at http://pi.hole/admin or http://${IPV4_ADDRESS%/*}/admin

Your Admin Webpage login password is ${pwstring}"
   fi

    # Final completion message to user
    whiptail --msgbox --backtitle "Make it so." --title "Installation Complete!" "Configure your devices to use the Pi-hole as their DNS server using:

IPv4:	${IPV4_ADDRESS%/*}
IPv6:	${IPV6_ADDRESS:-"Not Configured"}

If you set a new IP address, you should restart the Pi.

The install log is in /etc/pihole.

${additional}" ${r} ${c}
}

update_dialogs() {
    # If pihole -r "reconfigure" option was selected,
    if [[ "${reconfigure}" = true ]]; then
        # set some variables that will be used
        opt1a="Repair"
        opt1b="This will retain existing settings"
        strAdd="You will remain on the same version"
    # Otherwise,
    else
        # set some variables with different values
        opt1a="Update"
        opt1b="This will retain existing settings."
        strAdd="You will be updated to the latest version."
    fi
    opt2a="Reconfigure"
    opt2b="This will reset your Pi-hole and allow you to enter new settings."

    # Display the information to the user
    UpdateCmd=$(whiptail --title "Existing Install Detected!" --menu "\\n\\nWe have detected an existing install.\\n\\nPlease choose from the following options: \\n($strAdd)" ${r} ${c} 2 \
    "${opt1a}"  "${opt1b}" \
    "${opt2a}"  "${opt2b}" 3>&2 2>&1 1>&3) || \
    { printf "  %bCancel was selected, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }

    # Set the variable based on if the user chooses
    case ${UpdateCmd} in
        # repair, or
        ${opt1a})
            printf "  %b %s option selected\\n" "${INFO}" "${opt1a}"
            useUpdateVars=true
            ;;
        # reconfigure,
        ${opt2a})
            printf "  %b %s option selected\\n" "${INFO}" "${opt2a}"
            useUpdateVars=false
            ;;
    esac
}

check_download_exists() {
    status=$(curl --head --silent "https://ftl.pi-hole.net/${1}" | head -n 1)
    if grep -q "404" <<< "$status"; then
        return 1
    else
        return 0
    fi
}

fully_fetch_repo() {
    # Add upstream branches to shallow clone
    local directory="${1}"

    cd "${directory}" || return 1
    if is_repo "${directory}"; then
        git remote set-branches origin '*' || return 1
        git fetch --quiet || return 1
    else
        return 1
    fi
    return 0
}

get_available_branches() {
    # Return available branches
    local directory
    directory="${1}"
    local output

    cd "${directory}" || return 1
    # Get reachable remote branches, but store STDERR as STDOUT variable
    output=$( { git ls-remote --heads --quiet | cut -d'/' -f3- -; } 2>&1 )
    # echo status for calling function to capture
    echo "$output"
    return
}

fetch_checkout_pull_branch() {
    # Check out specified branch
    local directory
    directory="${1}"
    local branch
    branch="${2}"

    # Set the reference for the requested branch, fetch, check it put and pull it
    cd "${directory}" || return 1
    git remote set-branches origin "${branch}" || return 1
    git stash --all --quiet &> /dev/null || true
    git clean --quiet --force -d || true
    git fetch --quiet || return 1
    checkout_pull_branch "${directory}" "${branch}" || return 1
}

checkout_pull_branch() {
    # Check out specified branch
    local directory
    directory="${1}"
    local branch
    branch="${2}"
    local oldbranch

    cd "${directory}" || return 1

    oldbranch="$(git symbolic-ref HEAD)"

    str="Switching to branch: '${branch}' from '${oldbranch}'"
    printf "  %b %s" "${INFO}" "$str"
    git checkout "${branch}" --quiet || return 1
    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "$str"

    git_pull=$(git pull || return 1)

    if [[ "$git_pull" == *"up-to-date"* ]]; then
        printf "  %b %s\\n" "${INFO}" "${git_pull}"
    else
        printf "%s\\n" "$git_pull"
    fi

    return 0
}

clone_or_update_repos() {
    # If the user wants to reconfigure,
    if [[ "${reconfigure}" == true ]]; then
        printf "  %b Performing reconfiguration, skipping download of local repos\\n" "${INFO}"
        # Reset the Core repo
        resetRepo ${PI_HOLE_LOCAL_REPO} || \
        { printf "  %bUnable to reset %s, exiting installer%b\\n" "${COL_LIGHT_RED}" "${PI_HOLE_LOCAL_REPO}" "${COL_NC}"; \
        exit 1; \
        }
        # If the Web interface was installed,
        if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then
            # reset it's repo
            resetRepo ${webInterfaceDir} || \
            { printf "  %bUnable to reset %s, exiting installer%b\\n" "${COL_LIGHT_RED}" "${webInterfaceDir}" "${COL_NC}"; \
            exit 1; \
            }
        fi
    # Otherwise, a repair is happening
    else
        # so get git files for Core
        getGitFiles ${PI_HOLE_LOCAL_REPO} ${piholeGitUrl} || \
        { printf "  %bUnable to clone %s into %s, unable to continue%b\\n" "${COL_LIGHT_RED}" "${piholeGitUrl}" "${PI_HOLE_LOCAL_REPO}" "${COL_NC}"; \
        exit 1; \
        }
        # If the Web interface was installed,
        if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then
            # get the Web git files
            getGitFiles ${webInterfaceDir} ${webInterfaceGitUrl} || \
            { printf "  %bUnable to clone %s into ${webInterfaceDir}, exiting installer%b\\n" "${COL_LIGHT_RED}" "${webInterfaceGitUrl}" "${COL_NC}"; \
            exit 1; \
            }
        fi
    fi
}

# Download FTL binary to random temp directory and install FTL binary
FTLinstall() {
    # Local, named variables
    local latesttag
    local str="Downloading and Installing FTL"
    printf "  %b %s..." "${INFO}" "${str}"

    # Find the latest version tag for FTL
    latesttag=$(curl -sI https://github.com/pi-hole/FTL/releases/latest | grep "Location" | awk -F '/' '{print $NF}')
    # Tags should always start with v, check for that.
    if [[ ! "${latesttag}" == v* ]]; then
        printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
        printf "  %bError: Unable to get latest release location from GitHub%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"
        return 1
    fi

    # Move into the temp ftl directory
    pushd "$(mktemp -d)" > /dev/null || { printf "Unable to make temporary directory for FTL binary download\\n"; return 1; }

    # Always replace pihole-FTL.service
    install -T -m 0755 "${PI_HOLE_LOCAL_REPO}/advanced/Templates/pihole-FTL.service" "/etc/init.d/pihole-FTL"

    local ftlBranch
    local url

    if [[ -f "/etc/pihole/ftlbranch" ]];then
        ftlBranch=$(</etc/pihole/ftlbranch)
    else
        ftlBranch="master"
    fi

    # Determine which version of FTL to download
    if [[ "${ftlBranch}" == "master" ]];then
        url="https://github.com/pi-hole/FTL/releases/download/${latesttag%$'\r'}"
    else
        url="https://ftl.pi-hole.net/${ftlBranch}"
    fi

    # If the download worked,
    if curl -sSL --fail "${url}/${binary}" -o "${binary}"; then
        # get sha1 of the binary we just downloaded for verification.
        curl -sSL --fail "${url}/${binary}.sha1" -o "${binary}.sha1"

        # If we downloaded binary file (as opposed to text),
        if sha1sum --status --quiet -c "${binary}".sha1; then
            printf "transferred... "

            # Stop pihole-FTL service if available
            stop_service pihole-FTL &> /dev/null

            # Install the new version with the correct permissions
            install -T -m 0755 "${binary}" /usr/bin/pihole-FTL

            # Move back into the original directory the user was in
            popd > /dev/null || { printf "Unable to return to original directory after FTL binary download.\\n"; return 1; }

            # Installed the FTL service
            printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
            return 0
        # Otherwise,
        else
            # the download failed, so just go back to the original directory
            popd > /dev/null || { printf "Unable to return to original directory after FTL binary download.\\n"; return 1; }
            printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
            printf "  %bError: Download of %s/%s failed (checksum error)%b\\n" "${COL_LIGHT_RED}" "${url}" "${binary}" "${COL_NC}"
            return 1
        fi
    # Otherwise,
    else
        popd > /dev/null || { printf "Unable to return to original directory after FTL binary download.\\n"; return 1; }
        printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
        # The URL could not be found
        printf "  %bError: URL %s/%s not found%b\\n" "${COL_LIGHT_RED}" "${url}" "${binary}" "${COL_NC}"
        return 1
    fi
}

disable_dnsmasq() {
    # dnsmasq can now be stopped and disabled if it exists
    if which dnsmasq &> /dev/null; then
        if check_service_active "dnsmasq";then
            printf "  %b FTL can now resolve DNS Queries without dnsmasq running separately\\n" "${INFO}"
            stop_service dnsmasq
            disable_service dnsmasq
        fi
    fi

    # Backup existing /etc/dnsmasq.conf if present and ensure that
    # /etc/dnsmasq.conf contains only "conf-dir=/etc/dnsmasq.d"
    local conffile="/etc/dnsmasq.conf"
    if [[ -f "${conffile}" ]]; then
        printf "  %b Backing up %s to %s.old\\n" "${INFO}" "${conffile}" "${conffile}"
        mv "${conffile}" "${conffile}.old"
    fi
    # Create /etc/dnsmasq.conf
    echo "conf-dir=/etc/dnsmasq.d" > "${conffile}"
}

get_binary_name() {
    # This gives the machine architecture which may be different from the OS architecture...
    local machine
    machine=$(uname -m)

    local str="Detecting architecture"
    printf "  %b %s..." "${INFO}" "${str}"
    # If the machine is arm or aarch
    if [[ "${machine}" == "arm"* || "${machine}" == *"aarch"* ]]; then
        # ARM
        #
        local rev
        rev=$(uname -m | sed "s/[^0-9]//g;")
        #
        local lib
        lib=$(ldd /bin/ls | grep -E '^\s*/lib' | awk '{ print $1 }')
        #
        if [[ "${lib}" == "/lib/ld-linux-aarch64.so.1" ]]; then
            printf "%b  %b Detected ARM-aarch64 architecture\\n" "${OVER}" "${TICK}"
            # set the binary to be used
            binary="pihole-FTL-aarch64-linux-gnu"
        #
        elif [[ "${lib}" == "/lib/ld-linux-armhf.so.3" ]]; then
            #
            if [[ "${rev}" -gt 6 ]]; then
                printf "%b  %b Detected ARM-hf architecture (armv7+)\\n" "${OVER}" "${TICK}"
                # set the binary to be used
                binary="pihole-FTL-arm-linux-gnueabihf"
            # Otherwise,
            else
                printf "%b  %b Detected ARM-hf architecture (armv6 or lower) Using ARM binary\\n" "${OVER}" "${TICK}"
                # set the binary to be used
                binary="pihole-FTL-arm-linux-gnueabi"
            fi
        else
            printf "%b  %b Detected ARM architecture\\n" "${OVER}" "${TICK}"
            # set the binary to be used
            binary="pihole-FTL-arm-linux-gnueabi"
        fi
    elif [[ "${machine}" == "x86_64" ]]; then
        # This gives the architecture of packages dpkg installs (for example, "i386")
        local dpkgarch
        dpkgarch=$(dpkg --print-architecture 2> /dev/null)

        # Special case: This is a 32 bit OS, installed on a 64 bit machine
        # -> change machine architecture to download the 32 bit executable
        if [[ "${dpkgarch}" == "i386" ]]; then
            printf "%b  %b Detected 32bit (i686) architecture\\n" "${OVER}" "${TICK}"
            binary="pihole-FTL-linux-x86_32"
        else
            # 64bit
            printf "%b  %b Detected x86_64 architecture\\n" "${OVER}" "${TICK}"
            # set the binary to be used
            binary="pihole-FTL-linux-x86_64"
        fi
    else
        # Something else - we try to use 32bit executable and warn the user
        if [[ ! "${machine}" == "i686" ]]; then
            printf "%b  %b %s...\\n" "${OVER}" "${CROSS}" "${str}"
            printf "  %b %bNot able to detect architecture (unknown: %s), trying 32bit executable%b\\n" "${INFO}" "${COL_LIGHT_RED}" "${machine}" "${COL_NC}"
            printf "  %b Contact Pi-hole Support if you experience issues (e.g: FTL not running)\\n" "${INFO}"
        else
            printf "%b  %b Detected 32bit (i686) architecture\\n" "${OVER}" "${TICK}"
        fi
        binary="pihole-FTL-linux-x86_32"
    fi
}

FTLcheckUpdate() {
    get_binary_name

    #In the next section we check to see if FTL is already installed (in case of pihole -r).
    #If the installed version matches the latest version, then check the installed sha1sum of the binary vs the remote sha1sum. If they do not match, then download
    printf "  %b Checking for existing FTL binary...\\n" "${INFO}"

    local ftlLoc
    ftlLoc=$(which pihole-FTL 2>/dev/null)

    local ftlBranch

    if [[ -f "/etc/pihole/ftlbranch" ]];then
        ftlBranch=$(</etc/pihole/ftlbranch)
    else
        ftlBranch="master"
    fi

    local remoteSha1
    local localSha1

    # if dnsmasq exists and is running at this point, force reinstall of FTL Binary
    if which dnsmasq &> /dev/null; then
        if check_service_active "dnsmasq";then
            return 0
        fi
    fi

    if [[ ! "${ftlBranch}" == "master" ]]; then
        #Check whether or not the binary for this FTL branch actually exists. If not, then there is no update!
        local path
        path="${ftlBranch}/${binary}"
        # shellcheck disable=SC1090
        if ! check_download_exists "$path"; then
            printf "  %b Branch \"%s\" is not available.\\n" "${INFO}" "${ftlBranch}"
            printf "  %b Use %bpihole checkout ftl [branchname]%b to switch to a valid branch.\\n" "${INFO}" "${COL_LIGHT_GREEN}" "${COL_NC}"
            return 2
        fi

        if [[ ${ftlLoc} ]]; then
            # We already have a pihole-FTL binary downloaded.
            # Alt branches don't have a tagged version against them, so just confirm the checksum of the local vs remote to decide whether we download or not
            remoteSha1=$(curl -sSL --fail "https://ftl.pi-hole.net/${ftlBranch}/${binary}.sha1" | cut -d ' ' -f 1)
            localSha1=$(sha1sum "$(which pihole-FTL)" | cut -d ' ' -f 1)

            if [[ "${remoteSha1}" != "${localSha1}" ]]; then
                printf "  %b Checksums do not match, downloading from ftl.pi-hole.net.\\n" "${INFO}"
                return 0
            else
                printf "  %b Checksum of installed binary matches remote. No need to download!\\n" "${INFO}"
                return 1
            fi
        else
            return 0
        fi
    else
        if [[ ${ftlLoc} ]]; then
            local FTLversion
            FTLversion=$(/usr/bin/pihole-FTL tag)
            local FTLlatesttag
            FTLlatesttag=$(curl -sI https://github.com/pi-hole/FTL/releases/latest | grep 'Location' | awk -F '/' '{print $NF}' | tr -d '\r\n')

            if [[ "${FTLversion}" != "${FTLlatesttag}" ]]; then
                return 0
            else
                printf "  %b Latest FTL Binary already installed (%s). Confirming Checksum...\\n" "${INFO}" "${FTLlatesttag}"

                remoteSha1=$(curl -sSL --fail "https://github.com/pi-hole/FTL/releases/download/${FTLversion%$'\r'}/${binary}.sha1" | cut -d ' ' -f 1)
                localSha1=$(sha1sum "$(which pihole-FTL)" | cut -d ' ' -f 1)

                if [[ "${remoteSha1}" != "${localSha1}" ]]; then
                    printf "  %b Corruption detected...\\n" "${INFO}"
                    return 0
                else
                    printf "  %b Checksum correct. No need to download!\\n" "${INFO}"
                    return 1
                fi
            fi
        else
            return 0
        fi
    fi
}

# Detect suitable FTL binary platform
FTLdetect() {
    printf "\\n  %b FTL Checks...\\n\\n" "${INFO}"

    if FTLcheckUpdate ; then
        FTLinstall || return 1
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
    # is meant to be a security measure so there is not a lingering file on the drive during the install process
    rm "$TEMPLOG"
}

copy_to_install_log() {
    # Copy the contents of file descriptor 3 into the install log
    # Since we use color codes such as '\e[1;33m', they should be removed
    sed 's/\[[0-9;]\{1,5\}m//g' < /proc/$$/fd/3 > "${installLogLoc}"
}

main() {
    ######## FIRST CHECK ########
    # Must be root to install
    local str="Root user check"
    printf "\\n"

    # If the user's id is zero,
    if [[ "${EUID}" -eq 0 ]]; then
        # they are root and all is good
        printf "  %b %s\\n" "${TICK}" "${str}"
        # Show the Pi-hole logo so people know it's genuine since the logo and name are trademarked
        show_ascii_berry
        make_temporary_log
    # Otherwise,
    else
        # They do not have enough privileges, so let the user know
        printf "  %b %s\\n" "${CROSS}" "${str}"
        printf "  %b %bScript called with non-root privileges%b\\n" "${INFO}" "${COL_LIGHT_RED}" "${COL_NC}"
        printf "      The Pi-hole requires elevated privileges to install and run\\n"
        printf "      Please check the installer for any concerns regarding this requirement\\n"
        printf "      Make sure to download this script from a trusted source\\n\\n"
        printf "  %b Sudo utility check" "${INFO}"

        # If the sudo command exists,
        if is_command sudo ; then
            printf "%b  %b Sudo utility check\\n" "${OVER}"  "${TICK}"
            # Download the install script and run it with admin rights
            exec curl -sSL https://raw.githubusercontent.com/pi-hole/pi-hole/master/automated%20install/basic-install.sh | sudo bash "$@"
            exit $?
        # Otherwise,
        else
            # Let them know they need to run it as root
            printf "%b  %b Sudo utility check\\n" "${OVER}" "${CROSS}"
            printf "  %b Sudo is needed for the Web Interface to run pihole commands\\n\\n" "${INFO}"
            printf "  %b %bPlease re-run this installer as root${COL_NC}\\n" "${INFO}" "${COL_LIGHT_RED}"
            exit 1
        fi
    fi

    # Check for supported distribution
    distro_check

    # If the setup variable file exists,
    if [[ -f "${setupVars}" ]]; then
        # if it's running unattended,
        if [[ "${runUnattended}" == true ]]; then
            printf "  %b Performing unattended setup, no whiptail dialogs will be displayed\\n" "${INFO}"
            # Use the setup variables
            useUpdateVars=true
            # also disable debconf-apt-progress dialogs
            export DEBIAN_FRONTEND="noninteractive"
        # Otherwise,
        else
            # show the available options (repair/reconfigure)
            update_dialogs
        fi
    fi

    # Start the installer
    # Verify there is enough disk space for the install
    if [[ "${skipSpaceCheck}" == true ]]; then
        printf "  %b Skipping free disk space verification\\n" "${INFO}"
    else
        verifyFreeDiskSpace
    fi

    # Update package cache
    update_package_cache || exit 1

    # Notify user of package availability
    notify_package_updates_available

    # Install packages used by this installation script
    install_dependent_packages INSTALLER_DEPS[@]

    # Check if SELinux is Enforcing
    checkSelinux

    if [[ "${useUpdateVars}" == false ]]; then
        # Display welcome dialogs
        welcomeDialogs
        # Create directory for Pi-hole storage
        mkdir -p /etc/pihole/
        # Determine available interfaces
        get_available_interfaces
        # Find interfaces and let the user choose one
        chooseInterface
        # Decide what upstream DNS Servers to use
        setDNS
        # Give the user a choice of blocklists to include in their install. Or not.
        chooseBlocklists
        # Let the user decide if they want to block ads over IPv4 and/or IPv6
        use4andor6
        # Let the user decide if they want the web interface to be installed automatically
        setAdminFlag
        # Let the user decide if they want query logging enabled...
        setLogging
        # Let the user decide the FTL privacy level
        setPrivacyLevel
    else
        # Setup adlist file if not exists
        installDefaultBlocklists

        # Source ${setupVars} to use predefined user variables in the functions
        source ${setupVars}

        # Get the privacy level if it exists (default is 0)
        if [[ -f "${PI_HOLE_CONFIG_DIR}/pihole-FTL.conf" ]]; then
            PRIVACY_LEVEL=$(sed -ne 's/PRIVACYLEVEL=\(.*\)/\1/p' "${PI_HOLE_CONFIG_DIR}/pihole-FTL.conf")

            # If no setting was found, default to 0
            PRIVACY_LEVEL="${PRIVACY_LEVEL:-0}"
        fi
    fi
    # Clone/Update the repos
    clone_or_update_repos

    # Install the Core dependencies
    local dep_install_list=("${PIHOLE_DEPS[@]}")
    if [[ "${INSTALL_WEB_SERVER}" == true ]]; then
        # Install the Web dependencies
        dep_install_list+=("${PIHOLE_WEB_DEPS[@]}")
    fi

    install_dependent_packages dep_install_list[@]
    unset dep_install_list

    # On some systems, lighttpd is not enabled on first install. We need to enable it here if the user
    # has chosen to install the web interface, else the `LIGHTTPD_ENABLED` check will fail
    if [[ "${INSTALL_WEB_SERVER}" == true ]]; then
        enable_service lighttpd
    fi
    # Determine if lighttpd is correctly enabled
    if check_service_active "lighttpd"; then
        LIGHTTPD_ENABLED=true
    else
        LIGHTTPD_ENABLED=false
    fi
    # Check if FTL is installed - do this early on as FTL is a hard dependency for Pi-hole
    if ! FTLdetect; then
        printf "  %b FTL Engine not installed\\n" "${CROSS}"
        exit 1
    fi

    # Install and log everything to a file
    installPihole | tee -a /proc/$$/fd/3

    # Copy the temp log file into final log location for storage
    copy_to_install_log

    if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then
        # Add password to web UI if there is none
        pw=""
        # If no password is set,
        if [[ $(grep 'WEBPASSWORD' -c /etc/pihole/setupVars.conf) == 0 ]] ; then
            # generate a random password
            pw=$(tr -dc _A-Z-a-z-0-9 < /dev/urandom | head -c 8)
            # shellcheck disable=SC1091
            . /opt/pihole/webpage.sh
            echo "WEBPASSWORD=$(HashPassword ${pw})" >> ${setupVars}
        fi
    fi

    # Check for and disable systemd-resolved-DNSStubListener before reloading resolved
    # DNSStubListener needs to remain in place for installer to download needed files,
    # so this change needs to be made after installation is complete,
    # but before starting or resarting the dnsmasq or ftl services
    disable_resolved_stublistener

    # If the Web server was installed,
    if [[ "${INSTALL_WEB_SERVER}" == true ]]; then

        if [[ "${LIGHTTPD_ENABLED}" == true ]]; then
            restart_service lighttpd
            enable_service lighttpd
        else
            printf "  %b Lighttpd is disabled, skipping service restart\\n" "${INFO}"
        fi
    fi

    printf "  %b Restarting services...\\n" "${INFO}"
    # Start services

    # Enable FTL
    # Ensure the service is enabled before trying to start it
    # Fixes a problem reported on Ubuntu 18.04 where trying to start
    # the service before enabling causes installer to exit
    enable_service pihole-FTL
    restart_service pihole-FTL

    # Download and compile the aggregated block list
    runGravity

    # Force an update of the updatechecker
    /opt/pihole/updatecheck.sh
    /opt/pihole/updatecheck.sh x remote

    if [[ "${useUpdateVars}" == false ]]; then
        displayFinalMessage "${pw}"
    fi

    # If the Web interface was installed,
    if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then
        # If there is a password,
        if (( ${#pw} > 0 )) ; then
            # display the password
            printf "  %b Web Interface password: %b%s%b\\n" "${INFO}" "${COL_LIGHT_GREEN}" "${pw}" "${COL_NC}"
            printf "  %b This can be changed using 'pihole -a -p'\\n\\n" "${INFO}"
        fi
    fi

    if [[ "${useUpdateVars}" == false ]]; then
        # If the Web interface was installed,
        if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then
            printf "  %b View the web interface at http://pi.hole/admin or http://%s/admin\\n\\n" "${INFO}" "${IPV4_ADDRESS%/*}"
        fi
        # Explain to the user how to use Pi-hole as their DNS server
        printf "  %b You may now configure your devices to use the Pi-hole as their DNS server\\n" "${INFO}"
        [[ -n "${IPV4_ADDRESS%/*}" ]] && printf "  %b Pi-hole DNS (IPv4): %s\\n" "${INFO}" "${IPV4_ADDRESS%/*}"
        [[ -n "${IPV6_ADDRESS}" ]] && printf "  %b Pi-hole DNS (IPv6): %s\\n" "${INFO}" "${IPV6_ADDRESS}"
        printf "  %b If you set a new IP address, please restart the server running the Pi-hole\\n" "${INFO}"
        INSTALL_TYPE="Installation"
    else
        INSTALL_TYPE="Update"
    fi

    # Display where the log file is
    printf "\\n  %b The install log is located at: %s\\n" "${INFO}" "${installLogLoc}"
    printf "%b%s Complete! %b\\n" "${COL_LIGHT_GREEN}" "${INSTALL_TYPE}" "${COL_NC}"

    if [[ "${INSTALL_TYPE}" == "Update" ]]; then
        printf "\\n"
        /usr/local/bin/pihole version --current
    fi
}

if [[ "${PH_TEST}" != true ]] ; then
    main "$@"
fi
