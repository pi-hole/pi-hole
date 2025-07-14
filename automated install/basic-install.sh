#!/usr/bin/env bash

# Pi-hole: A black hole for Internet advertisements
# (c) Pi-hole (https://pi-hole.net)
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

# Append common folders to the PATH to ensure that all basic commands are available.
# When using "su" an incomplete PATH could be passed: https://github.com/pi-hole/pi-hole/issues/3209
export PATH+=':/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'

# Trap any errors, then exit
trap abort INT QUIT TERM

######## VARIABLES #########
# For better maintainability, we store as much information that can change in variables
# This allows us to make a change in one place that can propagate to all instances of the variable
# These variables should all be GLOBAL variables, written in CAPS
# Local variables will be in lowercase and will exist only within functions
# It's still a work in progress, so you may see some variance in this guideline until it is complete

# Dialog result codes
# dialog code values can be set by environment variables, we only override if
# the env var is not set or empty.
: "${DIALOG_OK:=0}"
: "${DIALOG_CANCEL:=1}"
: "${DIALOG_ESC:=255}"

# List of supported DNS servers
DNS_SERVERS=$(
    cat <<EOM
Google (ECS, DNSSEC);8.8.8.8;8.8.4.4;2001:4860:4860:0:0:0:0:8888;2001:4860:4860:0:0:0:0:8844
OpenDNS (ECS, DNSSEC);208.67.222.222;208.67.220.220;2620:119:35::35;2620:119:53::53
Level3;4.2.2.1;4.2.2.2;;
Comodo;8.26.56.26;8.20.247.20;;
Quad9 (filtered, DNSSEC);9.9.9.9;149.112.112.112;2620:fe::fe;2620:fe::9
Quad9 (unfiltered, no DNSSEC);9.9.9.10;149.112.112.10;2620:fe::10;2620:fe::fe:10
Quad9 (filtered, ECS, DNSSEC);9.9.9.11;149.112.112.11;2620:fe::11;2620:fe::fe:11
Cloudflare (DNSSEC);1.1.1.1;1.0.0.1;2606:4700:4700::1111;2606:4700:4700::1001
EOM
)

DNS_SERVERS_IPV6_ONLY=$(
    cat <<EOM
Google (ECS, DNSSEC);2001:4860:4860:0:0:0:0:8888;2001:4860:4860:0:0:0:0:8844
OpenDNS (ECS, DNSSEC);2620:119:35::35;2620:119:53::53
Quad9 (filtered, DNSSEC);2620:fe::fe;2620:fe::9
Quad9 (unfiltered, no DNSSEC);2620:fe::10;2620:fe::fe:10
Quad9 (filtered, ECS, DNSSEC);2620:fe::11;2620:fe::fe:11
Cloudflare (DNSSEC);2606:4700:4700::1111;2606:4700:4700::1001
EOM
)

# Location for final installation log storage
installLogLoc="/etc/pihole/install.log"
# This is a file used for the colorized output
coltable="/opt/pihole/COL_TABLE"

# Root of the web server
webroot="/var/www/html"

# We clone (or update) two git repositories during the install. This helps to make sure that we always have the latest versions of the relevant files.
# web is used to set up the Web admin interface.
# Pi-hole contains various setup scripts and files which are critical to the installation.
# Search for "PI_HOLE_LOCAL_REPO" in this file to see all such scripts.
# Two notable scripts are gravity.sh (used to generate the HOSTS file) and advanced/Scripts/webpage.sh (used to install the Web admin interface)
webInterfaceGitUrl="https://github.com/pi-hole/web.git"
webInterfaceDir="${webroot}/admin"
piholeGitUrl="https://github.com/pi-hole/pi-hole.git"
PI_HOLE_LOCAL_REPO="/etc/.pihole"
# List of pihole scripts, stored in an array
PI_HOLE_FILES=(list piholeDebug piholeLogFlush setupLCD update version gravity uninstall webpage)
# This directory is where the Pi-hole scripts will be installed
PI_HOLE_INSTALL_DIR="/opt/pihole"
PI_HOLE_CONFIG_DIR="/etc/pihole"
PI_HOLE_BIN_DIR="/usr/local/bin"
PI_HOLE_V6_CONFIG="${PI_HOLE_CONFIG_DIR}/pihole.toml"
fresh_install=true

adlistFile="/etc/pihole/adlists.list"
# Pi-hole needs an IP address; to begin, these variables are empty since we don't know what the IP is until this script can run
IPV4_ADDRESS=${IPV4_ADDRESS}
IPV6_ADDRESS=${IPV6_ADDRESS}
# Give settings their default values. These may be changed by prompts later in the script.
QUERY_LOGGING=
PRIVACY_LEVEL=
PIHOLE_INTERFACE=

# Where old configs go to if a v6 migration is performed
V6_CONF_MIGRATION_DIR="/etc/pihole/migration_backup_v6"

if [ -z "${USER}" ]; then
    USER="$(id -un)"
fi

# dialog dimensions: Let dialog handle appropriate sizing.
r=20
c=70

# Content of Pi-hole's meta package control file on APT based systems
PIHOLE_META_PACKAGE_CONTROL_APT=$(
    cat <<EOM
Package: pihole-meta
Version: 0.4
Maintainer: Pi-hole team <adblock@pi-hole.net>
Architecture: all
Description: Pi-hole dependency meta package
Depends: awk,bash-completion,binutils,ca-certificates,cron|cron-daemon,curl,dialog,dnsutils,dns-root-data,git,grep,iproute2,iputils-ping,jq,libcap2,libcap2-bin,lshw,netcat-openbsd,procps,psmisc,sudo,unzip
Section: contrib/metapackages
Priority: optional
EOM
)

# Content of Pi-hole's meta package control file on RPM based systems
PIHOLE_META_PACKAGE_CONTROL_RPM=$(
    cat <<EOM
Name: pihole-meta
Version: 0.2
Release: 1
License: EUPL
BuildArch: noarch
Summary: Pi-hole dependency meta package
Requires: bash-completion,bind-utils,binutils,ca-certificates,chkconfig,cronie,curl,dialog,findutils,gawk,git,grep,iproute,jq,libcap,lshw,nmap-ncat,procps-ng,psmisc,sudo,unzip
%description
Pi-hole dependency meta package
%prep
%build
%files
%install
%changelog
* Wed May 28 2025 Pi-hole Team - 0.2
- Add gawk to the list of dependencies

* Sun Sep 29 2024 Pi-hole Team - 0.1
- First version being packaged
EOM
)

######## Undocumented Flags. Shhh ########
# These are undocumented flags; some of which we can use when repairing an installation
# The runUnattended flag is one example of this
repair=false
runUnattended=false
# Check arguments for the undocumented flags
for var in "$@"; do
    case "$var" in
    "--repair") repair=true ;;
    "--unattended") runUnattended=true ;;
    esac
done

# If the color table file exists,
if [[ -f "${coltable}" ]]; then
    # source it
    # shellcheck source="./advanced/Scripts/COL_TABLE"
    source "${coltable}"
# Otherwise,
else
    # Set these values so the installer can still run in color
    COL_NC='\e[0m' # No Color
    COL_GREEN='\e[1;32m'
    COL_RED='\e[1;31m'
    TICK="[${COL_GREEN}✓${COL_NC}]"
    CROSS="[${COL_RED}✗${COL_NC}]"
    INFO="[i]"
    OVER="\\r\\033[K"
fi

# A simple function that just echoes out our logo in ASCII format
# This lets users know that it is a Pi-hole, LLC product
show_ascii_berry() {
    echo -e "
        ${COL_GREEN}.;;,.
        .ccccc:,.
         :cccclll:.      ..,,
          :ccccclll.   ;ooodc
           'ccll:;ll .oooodc
             .;cll.;;looo:.
                 ${COL_RED}.. ','.
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

abort() {

    # remove any leftover build directory that may exist
    rm -rf /tmp/pihole-meta_*

    echo -e "\\n\\n  ${COL_RED}Installation was interrupted${COL_NC}\\n"
    echo -e "Pi-hole's dependencies might be already installed. If you want to remove them you can try to\\n"
    echo -e "a) run 'pihole uninstall' \\n"
    echo -e "b) Remove the meta-package 'pihole-meta' manually \\n"
    echo -e "E.g. sudo apt-get remove pihole-meta && apt-get autoremove \\n"
    exit 1
}

is_command() {
    # Checks to see if the given command (passed as a string argument) exists on the system.
    # The function returns 0 (success) if the command exists, and 1 if it doesn't.
    local check_command="$1"

    command -v "${check_command}" >/dev/null 2>&1
}

check_fresh_install() {
    # in case of an update (can be a v5 -> v6 or v6 -> v6 update) or repair
    if [[ -f "${PI_HOLE_V6_CONFIG}" ]] || [[ -f "/etc/pihole/setupVars.conf" ]]; then
        fresh_install=false
    fi
}

# Compatibility
package_manager_detect() {

    # First check to see if apt-get is installed.
    if is_command apt-get; then
        # Set some global variables here
        # We don't set them earlier since the installed package manager might be rpm, so these values would be different
        PKG_MANAGER="apt-get"
        # A variable to store the command used to update the package cache
        UPDATE_PKG_CACHE="${PKG_MANAGER} update"
        # The command we will use to actually install packages
        PKG_INSTALL="${PKG_MANAGER} -qq --no-install-recommends install"
        # grep -c will return 1 if there are no matches. This is an acceptable condition, so we OR TRUE to prevent set -e exiting the script.
        PKG_COUNT="${PKG_MANAGER} -s -o Debug::NoLocking=true upgrade | grep -c ^Inst || true"
        # The command we will use to remove packages (used in the uninstaller)
        PKG_REMOVE="${PKG_MANAGER} -y remove --purge"

    # If apt-get is not found, check for rpm.
    elif is_command rpm; then
        # Then check if dnf or yum is the package manager
        if is_command dnf; then
            PKG_MANAGER="dnf"
        else
            PKG_MANAGER="yum"
        fi

        # These variable names match the ones for apt-get. See above for an explanation of what they are for.
        PKG_INSTALL="${PKG_MANAGER} install -y"
        # CentOS package manager returns 100 when there are packages to update so we need to || true to prevent the script from exiting.
        PKG_COUNT="${PKG_MANAGER} check-update | grep -E '(.i686|.x86|.noarch|.arm|.src|.riscv64)' | wc -l || true"
        # The command we will use to remove packages (used in the uninstaller)
        PKG_REMOVE="${PKG_MANAGER} remove -y"
    # If neither apt-get or yum/dnf package managers were found
    else
        # we cannot install required packages
        printf "  %b No supported package manager found\\n" "${CROSS}"
        # so exit the installer
        exit 1
    fi
}

build_dependency_package(){
    # This function will build a package that contains all the dependencies needed for Pi-hole

    # remove any leftover build directory that may exist
    rm -rf /tmp/pihole-meta_*

    # Create a fresh build directory with random name
    local tempdir
    tempdir="$(mktemp --directory /tmp/pihole-meta_XXXXX)"
    chmod 0755 "${tempdir}"

    if is_command apt-get; then
        # move into the tmp directory
        pushd /tmp &>/dev/null || return 1

        # remove leftover package if it exists from previous runs
        rm -f /tmp/pihole-meta.deb

        # Prepare directory structure and control file
        mkdir -p "${tempdir}"/DEBIAN
        chmod 0755 "${tempdir}"/DEBIAN
        touch "${tempdir}"/DEBIAN/control

        # Write the control file
        echo "${PIHOLE_META_PACKAGE_CONTROL_APT}" > "${tempdir}"/DEBIAN/control

        # Build the package
        local str="Building dependency package pihole-meta.deb"
        printf "  %b %s..." "${INFO}" "${str}"

        if dpkg-deb --build --root-owner-group "${tempdir}" pihole-meta.deb  &>/dev/null; then
            printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
        else
            printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
            printf "%b Error: Building pihole-meta.deb failed. %b\\n" "${COL_RED}" "${COL_NC}"
            return 1
        fi

        # Move back into the directory the user started in
        popd &> /dev/null || return 1

    elif is_command rpm; then
        # move into the tmp directory
        pushd /tmp &>/dev/null || return 1

        # remove leftover package if it exists from previous runs
        rm -f /tmp/pihole-meta.rpm

        # Prepare directory structure and spec file
        mkdir -p "${tempdir}"/SPECS
        touch "${tempdir}"/SPECS/pihole-meta.spec
        echo "${PIHOLE_META_PACKAGE_CONTROL_RPM}" > "${tempdir}"/SPECS/pihole-meta.spec

        # check if we need to install the build dependencies
        if ! is_command rpmbuild; then
            local REMOVE_RPM_BUILD=true
            eval "${PKG_INSTALL}" "rpm-build"
        fi

        # Build the package
        local str="Building dependency package pihole-meta.rpm"
        printf "  %b %s..." "${INFO}" "${str}"

        if rpmbuild -bb "${tempdir}"/SPECS/pihole-meta.spec --define "_topdir ${tempdir}" &>/dev/null; then
            printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
        else
            printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
            printf "%b Error: Building pihole-meta.rpm failed. %b\\n" "${COL_RED}" "${COL_NC}"
            return 1
        fi

        # Move the package to the /tmp directory
        mv "${tempdir}"/RPMS/noarch/pihole-meta*.rpm /tmp/pihole-meta.rpm

        # Remove the build dependencies when we've installed them
        if [ -n "${REMOVE_RPM_BUILD}" ]; then
            eval "${PKG_REMOVE}" "rpm-build"
        fi

        # Move back into the directory the user started in
        popd &> /dev/null || return 1

    # If neither apt-get or yum/dnf package managers were found
    else
        # we cannot build required packages
        printf "  %b No supported package manager found\\n" "${CROSS}"
        # so exit the installer
        exit 1
    fi

    # Remove the build directory
    rm -rf "${tempdir}"
}

# A function for checking if a directory is a git repository
is_repo() {
    # Use a named, local variable instead of the vague $1, which is the first argument passed to this function
    # These local variables should always be lowercase
    local directory="${1}"
    # A variable to store the return code
    local rc
    # If the first argument passed to this function is a directory,
    if [[ -d "${directory}" ]]; then
        # move into the directory
        pushd "${directory}" &>/dev/null || return 1
        # Use git to check if the directory is a repo
        # git -C is not used here to support git versions older than 1.8.4
        git status --short &> /dev/null || rc=$?
        # Move back into the directory the user started in
        popd &> /dev/null || return 1
    else
        # Set a non-zero return code if directory does not exist
        rc=1
    fi
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
        # Return with a 1 to exit the installer. We don't want to overwrite what could already be here in case it is not ours
        str="Unable to clone ${remoteRepo} into ${directory} : Directory already exists"
        printf "%b  %b%s\\n" "${OVER}" "${CROSS}" "${str}"
        return 1
    fi
    # Clone the repo and return the return code from this command
    git clone -q --depth 20 "${remoteRepo}" "${directory}" &>/dev/null || return $?
    # Move into the directory that was passed as an argument
    pushd "${directory}" &>/dev/null || return 1
    # Check current branch. If it is master, then reset to the latest available tag.
    # In case extra commits have been added after tagging/release (i.e in case of metadata updates/README.MD tweaks)
    curBranch=$(git rev-parse --abbrev-ref HEAD)
    if [[ "${curBranch}" == "master" ]]; then
        # If we're calling make_repo() then it should always be master, we may not need to check.
        git reset --hard "$(git describe --abbrev=0 --tags)" || return $?
    fi
    # Show a colored message showing it's status
    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
    # Data in the repositories is public anyway so we can make it readable by everyone (+r to keep executable permission if already set by git)
    chmod -R a+rX "${directory}"
    # Move back into the original directory
    popd &>/dev/null || return 1
    return 0
}

# We need to make sure the repos are up-to-date so we can effectively install Clean out the directory if it exists for git to clone into
update_repo() {
    # Use named, local variables
    # As you can see, these are the same variable names used in the last function,
    # but since they are local, their scope does not go beyond this function
    # This helps prevent the wrong value from being assigned if you were to set the variable as a GLOBAL one
    local directory="${1}"
    local curBranch

    # A variable to store the message we want to display;
    # Again, it's useful to store these in variables in case we need to reuse or change the message;
    # we only need to make one change here
    local str="Update repo in ${1}"
    # Move into the directory that was passed as an argument
    pushd "${directory}" &>/dev/null || return 1
    # Let the user know what's happening
    printf "  %b %s..." "${INFO}" "${str}"
    # Stash any local commits as they conflict with our working code
    git stash --all --quiet &>/dev/null || true # Okay for stash failure
    git clean --quiet --force -d || true        # Okay for already clean directory
    # Pull the latest commits
    git pull --no-rebase --quiet &>/dev/null || return $?
    # Check current branch. If it is master, then reset to the latest available tag.
    # In case extra commits have been added after tagging/release (i.e in case of metadata updates/README.MD tweaks)
    curBranch=$(git rev-parse --abbrev-ref HEAD)
    if [[ "${curBranch}" == "master" ]]; then
        git reset --hard "$(git describe --abbrev=0 --tags)" || return $?
    fi
    # Show a completion message
    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
    # Data in the repositories is public anyway so we can make it readable by everyone (+r to keep executable permission if already set by git)
    chmod -R a+rX "${directory}"
    # Move back into the original directory
    popd &>/dev/null || return 1
    return 0
}

# A function that combines the previous git functions to update or clone a repo
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
        update_repo "${directory}" || {
            printf "\\n  %b: Could not update local repository. Contact support.%b\\n" "${COL_RED}" "${COL_NC}"
            exit 1
        }
    # If it's not a .git repo,
    else
        # Show an error
        printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
        # Attempt to make the repository, showing an error on failure
        make_repo "${directory}" "${remoteRepo}" || {
            printf "\\n  %bError: Could not update local repository. Contact support.%b\\n" "${COL_RED}" "${COL_NC}"
            exit 1
        }
    fi
    echo ""
    # Success via one of the two branches, as the commands would exit if they failed.
    return 0
}

# Reset a repo to get rid of any local changed
resetRepo() {
    # Use named variables for arguments
    local directory="${1}"
    # Move into the directory
    pushd "${directory}" &>/dev/null || return 1
    # Store the message in a variable
    str="Resetting repository within ${1}..."
    # Show the message
    printf "  %b %s..." "${INFO}" "${str}"
    # Use git to remove the local changes
    git reset --hard &>/dev/null || return $?
    # Data in the repositories is public anyway so we can make it readable by everyone (+r to keep executable permission if already set by git)
    chmod -R a+rX "${directory}"
    # And show the status
    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
    # Return to where we came from
    popd &>/dev/null || return 1
    # Function succeeded, as "git reset" would have triggered a return earlier if it failed
    return 0
}

find_IPv4_information() {
    # Detects IPv4 address used for communication to WAN addresses.
    # Accepts no arguments, returns no values.

    # Named, local variables
    local route
    local IPv4bare

    # Find IP used to route to outside world by checking the route to Google's public DNS server
    if ! route="$(ip route get 8.8.8.8 2> /dev/null)"; then
        printf "  %b No IPv4 route was detected.\n" "${INFO}"
        IPV4_ADDRESS=""
        return
    fi

    # Get just the interface IPv4 address
    # shellcheck disable=SC2059,SC2086
    # disabled as we intentionally want to split on whitespace and have printf populate
    # the variable with just the first field.
    printf -v IPv4bare "$(printf ${route#*src })"

    if ! valid_ip "${IPv4bare}"; then
        IPv4bare="127.0.0.1"
    fi

    # Append the CIDR notation to the IP address, if valid_ip fails this should return 127.0.0.1/8
    IPV4_ADDRESS=$(ip -oneline -family inet address show | grep "${IPv4bare}/" | awk '{print $4}' | awk 'END {print}')
}

confirm_ipv6_only() {
    # Confirm from user before IPv6 only install

    dialog --no-shadow --output-fd 1 \
--no-button "Exit" --yes-button "Install IPv6 ONLY" \
--yesno "\\n\\nWARNING - no valid IPv4 route detected.\\n\\n\
This may be due to a temporary connectivity issue,\\n\
or you may be installing on an IPv6 only system.\\n\\n\
Do you wish to continue with an IPv6-only installation?\\n\\n" \
        "${r}" "${c}" && result=0 || result="$?"

    case "${result}" in
    "${DIALOG_CANCEL}" | "${DIALOG_ESC}")
        printf "  %b Installer exited at IPv6 only message.\\n" "${INFO}"
        exit 1
    ;;
    esac

    DNS_SERVERS="$DNS_SERVERS_IPV6_ONLY"
    printf "  %b Proceeding with IPv6 only installation.\\n" "${INFO}"
}

# Get available interfaces that are UP
get_available_interfaces() {
    # There may be more than one so it's all stored in a variable
    # The ip command list all interfaces that are in the up state
    # The awk command filters out any interfaces that have the LOOPBACK flag set
    # while using the characters ": " or "@" as a field separator for awk
    availableInterfaces=$(ip --oneline link show up | awk -F ': |@' '!/<.*LOOPBACK.*>/ {print $2}')
}

# A function for displaying the dialogs the user sees when first running the installer
welcomeDialogs() {
    # Display the welcome dialog using an appropriately sized window via the calculation conducted earlier in the script
    dialog --no-shadow --clear --keep-tite \
        --backtitle "Welcome" \
        --title "Pi-hole Automated Installer" \
        --msgbox "\\n\\nThis installer will transform your device into a network-wide ad blocker!" \
        "${r}" "${c}" \
        --and-widget --clear \
        --backtitle "Support Pi-hole" \
        --title "Open Source Software" \
        --msgbox "\\n\\nThe Pi-hole is free, but powered by your donations:  https://pi-hole.net/donate/" \
        "${r}" "${c}" \
        --and-widget --clear \
        --colors \
        --backtitle "Initiating network interface" \
        --title "Static IP Needed" \
        --no-button "Exit" --yes-button "Continue" \
        --defaultno \
        --yesno "\\n\\nThe Pi-hole is a SERVER so it needs a STATIC IP ADDRESS to function properly.\\n\\n\
\\Zb\\Z1IMPORTANT:\\Zn If you have not already done so, you must ensure that this device has a static IP.\\n\\n\
Depending on your operating system, there are many ways to achieve this, through DHCP reservation, or by manually assigning one.\\n\\n\
Please continue when the static addressing has been configured." \
        "${r}" "${c}" && result=0 || result="$?"

    case "${result}" in
    "${DIALOG_CANCEL}" | "${DIALOG_ESC}")
        printf "  %b Installer exited at static IP message.\\n" "${INFO}"
        exit 1
        ;;
    esac
}

# A function that lets the user pick an interface to use with Pi-hole
chooseInterface() {
    # Turn the available interfaces into a string so it can be used with dialog
    local interfacesList
    # Number of available interfaces
    local interfaceCount

    # POSIX compliant way to get the number of elements in an array
    interfaceCount=$(printf "%s\n" "${availableInterfaces}" | wc -l)

    # If there is one interface,
    if [[ "${interfaceCount}" -eq 1 ]]; then
        # Set it as the interface to use since there is no other option
        PIHOLE_INTERFACE="${availableInterfaces}"
    # Otherwise,
    else
        # Set status for the first entry to be selected
        status="ON"

        # While reading through the available interfaces
        for interface in ${availableInterfaces}; do
            # Put all these interfaces into a string
            interfacesList="${interfacesList}${interface} available ${status} "
            # All further interfaces are deselected
            status="OFF"
        done
        # Disable check for double quote here as we are passing a string with spaces
        PIHOLE_INTERFACE=$(dialog --no-shadow --keep-tite --output-fd 1 \
            --cancel-label "Exit" --ok-label "Select" \
            --radiolist "Choose An Interface (press space to toggle selection)" \
            ${r} ${c} "${interfaceCount}" ${interfacesList})

        result=$?
        case ${result} in
        "${DIALOG_CANCEL}" | "${DIALOG_ESC}")
            # Show an error message and exit
            printf "  %b %s\\n" "${CROSS}" "No interface selected, exiting installer"
            exit 1
            ;;
        esac

        printf "  %b Using interface: %s\\n" "${INFO}" "${PIHOLE_INTERFACE}"
    fi
}

# This lets us prefer ULA addresses over GUA
# This caused problems for some users when their ISP changed their IPv6 addresses
# See https://github.com/pi-hole/pi-hole/issues/1473#issuecomment-301745953
testIPv6() {
    # first will contain fda2 (ULA)
    printf -v first "%s" "${1%%:*}"
    # value1 will contain 253 which is the decimal value corresponding to 0xFD
    value1=$(((0x$first) / 256))
    # value2 will contain 162 which is the decimal value corresponding to 0xA2
    value2=$(((0x$first) % 256))
    # the ULA test is testing for fc00::/7 according to RFC 4193
    if (((value1 & 254) == 252)); then
        # echoing result to calling function as return value
        echo "ULA"
    fi
    # the GUA test is testing for 2000::/3 according to RFC 4291
    if (((value1 & 112) == 32)); then
        # echoing result to calling function as return value
        echo "GUA"
    fi
    # the LL test is testing for fe80::/10 according to RFC 4193
    if (((value1) == 254)) && (((value2 & 192) == 128)); then
        # echoing result to calling function as return value
        echo "Link-local"
    fi
}

find_IPv6_information() {
    # Detects IPv6 address used for communication to WAN addresses.
    mapfile -t IPV6_ADDRESSES <<<"$(ip -6 address | grep 'scope global' | awk '{print $2}')"

    # For each address in the array above, determine the type of IPv6 address it is
    for i in "${IPV6_ADDRESSES[@]}"; do
        # Check if it's ULA, GUA, or LL by using the function created earlier
        result=$(testIPv6 "$i")
        # If it's a ULA address, use it and store it as a global variable
        [[ "${result}" == "ULA" ]] && ULA_ADDRESS="${i%/*}"
        # If it's a GUA address, use it and store it as a global variable
        [[ "${result}" == "GUA" ]] && GUA_ADDRESS="${i%/*}"
        # Else if it's a Link-local address, we cannot use it, so just continue
    done

    # Determine which address to be used: Prefer ULA over GUA or don't use any if none found
    # If the ULA_ADDRESS contains a value,
    if [[ -n "${ULA_ADDRESS}" ]]; then
        # set the IPv6 address to the ULA address
        IPV6_ADDRESS="${ULA_ADDRESS}"
        # Show this info to the user
        printf "  %b Found IPv6 ULA address\\n" "${INFO}"
    # Otherwise, if the GUA_ADDRESS has a value,
    elif [[ -n "${GUA_ADDRESS}" ]]; then
        # Let the user know
        printf "  %b Found IPv6 GUA address\\n" "${INFO}"
        # And assign it to the global variable
        IPV6_ADDRESS="${GUA_ADDRESS}"
    # If none of those work,
    else
        printf "  %b Unable to find IPv6 ULA/GUA address\\n" "${INFO}"
        # So set the variable to be empty
        IPV6_ADDRESS=""
    fi
}

# A function to collect IPv4 and IPv6 information of the device
collect_v4andv6_information() {
    find_IPv4_information
    printf "  %b IPv4 address: %s\\n" "${INFO}" "${IPV4_ADDRESS}"
    find_IPv6_information
    printf "  %b IPv6 address: %s\\n" "${INFO}" "${IPV6_ADDRESS}"
    if [ "$IPV4_ADDRESS" == "" ] && [ "$IPV6_ADDRESS" != "" ]; then
        confirm_ipv6_only
    fi
}

# Check an IP address to see if it is a valid one
valid_ip() {
    # Local, named variables
    local ip=${1}
    local stat=1

    # Regex matching one IPv4 component, i.e. an integer from 0 to 255.
    # See https://tools.ietf.org/html/rfc1340
    local ipv4elem="(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)"
    # Regex matching an optional port (starting with '#') range of 1-65536
    local portelem="(#(6553[0-5]|655[0-2][0-9]|65[0-4][0-9]{2}|6[0-4][0-9]{3}|[1-5][0-9]{4}|[1-9][0-9]{0,3}|0))?"
    # Build a full IPv4 regex from the above subexpressions
    local regex="^${ipv4elem}\\.${ipv4elem}\\.${ipv4elem}\\.${ipv4elem}${portelem}$"

    # Evaluate the regex, and return the result
    [[ $ip =~ ${regex} ]]

    stat=$?
    return "${stat}"
}

valid_ip6() {
    local ip=${1}
    local stat=1

    # Regex matching one IPv6 element, i.e. a hex value from 0000 to FFFF
    local ipv6elem="[0-9a-fA-F]{1,4}"
    # Regex matching an IPv6 CIDR, i.e. 1 to 128
    local v6cidr="(\\/([1-9]|[1-9][0-9]|1[0-1][0-9]|12[0-8])){0,1}"
    # Regex matching an optional port (starting with '#') range of 1-65536
    local portelem="(#(6553[0-5]|655[0-2][0-9]|65[0-4][0-9]{2}|6[0-4][0-9]{3}|[1-5][0-9]{4}|[1-9][0-9]{0,3}|0))?"
    # Build a full IPv6 regex from the above subexpressions
    local regex="^(((${ipv6elem}))*((:${ipv6elem}))*::((${ipv6elem}))*((:${ipv6elem}))*|((${ipv6elem}))((:${ipv6elem})){7})${v6cidr}${portelem}$"

    # Evaluate the regex, and return the result
    [[ ${ip} =~ ${regex} ]]

    stat=$?
    return "${stat}"
}

# A function to choose the upstream DNS provider(s)
setDNS() {
    # Local, named variables
    local DNSSettingsCorrect

    # In an array, list the available upstream providers
    DNSChooseOptions=()
    local DNSServerCount=0
    # Save the old Internal Field Separator in a variable,
    OIFS=$IFS
    # and set the new one to newline
    IFS=$'\n'
    # Put the DNS Servers into an array
    for DNSServer in ${DNS_SERVERS}; do
        DNSName="$(cut -d';' -f1 <<<"${DNSServer}")"
        DNSChooseOptions[DNSServerCount]="${DNSName}"
        ((DNSServerCount = DNSServerCount + 1))
        DNSChooseOptions[DNSServerCount]=""
        ((DNSServerCount = DNSServerCount + 1))
    done
    DNSChooseOptions[DNSServerCount]="Custom"
    ((DNSServerCount = DNSServerCount + 1))
    DNSChooseOptions[DNSServerCount]=""
    # Restore the IFS to what it was
    IFS=${OIFS}
    # In a dialog, show the options
    DNSchoices=$(dialog --no-shadow --keep-tite --output-fd 1 \
        --cancel-label "Exit" \
        --menu "Select Upstream DNS Provider. To use your own, select Custom." "${r}" "${c}" 7 \
        "${DNSChooseOptions[@]}")

    result=$?
    case ${result} in
    "${DIALOG_CANCEL}" | "${DIALOG_ESC}")
        printf "  %b Cancel was selected, exiting installer%b\\n" "${COL_RED}" "${COL_NC}"
        exit 1
        ;;
    esac

    # Depending on the user's choice, set the GLOBAL variables to the IP of the respective provider
    if [[ "${DNSchoices}" == "Custom" ]]; then
        # Loop until we have a valid DNS setting
        until [[ "${DNSSettingsCorrect}" = True ]]; do
            # Signal value, to be used if the user inputs an invalid IP address
            strInvalid="Invalid"
            if [[ ! "${PIHOLE_DNS_1}" ]]; then
                if [[ ! "${PIHOLE_DNS_2}" ]]; then
                    # If the first and second upstream servers do not exist, do not prepopulate an IP address
                    prePopulate=""
                else
                    # Otherwise, prepopulate the dialogue with the appropriate DNS value(s)
                    prePopulate=", ${PIHOLE_DNS_2}"
                fi
            elif [[ "${PIHOLE_DNS_1}" ]] && [[ ! "${PIHOLE_DNS_2}" ]]; then
                prePopulate="${PIHOLE_DNS_1}"
            elif [[ "${PIHOLE_DNS_1}" ]] && [[ "${PIHOLE_DNS_2}" ]]; then
                prePopulate="${PIHOLE_DNS_1}, ${PIHOLE_DNS_2}"
            fi

            # Prompt the user to enter custom upstream servers
            piholeDNS=$(dialog --no-shadow --keep-tite --output-fd 1 \
                --cancel-label "Exit" \
                --backtitle "Specify Upstream DNS Provider(s)" \
                --inputbox "Enter your desired upstream DNS provider(s), separated by a comma.\
If you want to specify a port other than 53, separate it with a hash.\
\\n\\nFor example '8.8.8.8, 8.8.4.4' or '127.0.0.1#5335'" \
                "${r}" "${c}" "${prePopulate}")

            result=$?
            case ${result} in
            "${DIALOG_CANCEL}" | "${DIALOG_ESC}")
                printf "  %b Cancel was selected, exiting installer%b\\n" "${COL_RED}" "${COL_NC}"
                exit 1
                ;;
            esac

            # Clean user input and replace whitespace with comma.
            piholeDNS=$(sed 's/[, \t]\+/,/g' <<<"${piholeDNS}")

            # Separate the user input into the two DNS values (separated by a comma)
            printf -v PIHOLE_DNS_1 "%s" "${piholeDNS%%,*}"
            printf -v PIHOLE_DNS_2 "%s" "${piholeDNS##*,}"

            # If the first DNS value is invalid (neither IPv4 nor IPv6) or empty, set PIHOLE_DNS_1="Invalid"
            if ! valid_ip "${PIHOLE_DNS_1}" && ! valid_ip6 "${PIHOLE_DNS_1}" || [[ -z "${PIHOLE_DNS_1}" ]]; then
                PIHOLE_DNS_1=${strInvalid}
            fi
            # If the second DNS value is invalid but not empty, set PIHOLE_DNS_2="Invalid"
            if ! valid_ip "${PIHOLE_DNS_2}" && ! valid_ip6 "${PIHOLE_DNS_2}" && [[ -n "${PIHOLE_DNS_2}" ]]; then
                PIHOLE_DNS_2=${strInvalid}
            fi
            # If either of the DNS servers are invalid,
            if [[ "${PIHOLE_DNS_1}" == "${strInvalid}" ]] || [[ "${PIHOLE_DNS_2}" == "${strInvalid}" ]]; then
                # explain this to the user,
                dialog --no-shadow --keep-tite \
                    --title "Invalid IP Address(es)" \
                    --backtitle "Invalid IP" \
                    --msgbox "\\nOne or both of the entered IP addresses were invalid. Please try again.\
\\n\\nInvalid IPs: ${PIHOLE_DNS_1}, ${PIHOLE_DNS_2}" \
                    "${r}" "${c}"

                # set the variables back to nothing,
                if [[ "${PIHOLE_DNS_1}" == "${strInvalid}" ]]; then
                    PIHOLE_DNS_1=""
                fi
                if [[ "${PIHOLE_DNS_2}" == "${strInvalid}" ]]; then
                    PIHOLE_DNS_2=""
                fi
                # and continue the loop.
                DNSSettingsCorrect=False
            else
                dialog --no-shadow --no-collapse --keep-tite \
                    --backtitle "Specify Upstream DNS Provider(s)" \
                    --title "Upstream DNS Provider(s)" \
                    --yesno "Are these settings correct?\\n"$'\t'"DNS Server 1:"$'\t'"${PIHOLE_DNS_1}\\n"$'\t'"DNS Server 2:"$'\t'"${PIHOLE_DNS_2}" \
                    "${r}" "${c}" && result=0 || result=$?

                case ${result} in
                "${DIALOG_OK}")
                    DNSSettingsCorrect=True
                    ;;
                "${DIALOG_CANCEL}")
                    DNSSettingsCorrect=False
                    ;;
                "${DIALOG_ESC}")
                    printf "  %b Escape pressed, exiting installer at DNS Settings%b\\n" "${COL_RED}" "${COL_NC}"
                    exit 1
                    ;;
                esac
            fi
        done
    else
        # Save the old Internal Field Separator in a variable,
        OIFS=$IFS
        # and set the new one to newline
        IFS=$'\n'
        for DNSServer in ${DNS_SERVERS}; do
            DNSName="$(cut -d';' -f1 <<<"${DNSServer}")"
            if [[ "${DNSchoices}" == "${DNSName}" ]]; then
                PIHOLE_DNS_1="$(cut -d';' -f2 <<<"${DNSServer}")"
                PIHOLE_DNS_2="$(cut -d';' -f3 <<<"${DNSServer}")"
                break
            fi
        done
        # Restore the IFS to what it was
        IFS=${OIFS}
    fi

    # Display final selection
    local DNSIP=${PIHOLE_DNS_1}
    [[ -z ${PIHOLE_DNS_2} ]] || DNSIP+=", ${PIHOLE_DNS_2}"
    printf "  %b Using upstream DNS: %s (%s)\\n" "${INFO}" "${DNSchoices}" "${DNSIP}"
}

# Allow the user to enable/disable logging
setLogging() {
    # Ask the user if they want to enable logging
    dialog --no-shadow --keep-tite \
        --backtitle "Pihole Installation" \
        --title "Enable Logging" \
        --yesno "\\n\\nWould you like to enable query logging?" \
        "${r}" "${c}" && result=0 || result=$?

    case ${result} in
    "${DIALOG_OK}")
        # If they chose yes,
        printf "  %b Query Logging on.\\n" "${INFO}"
        QUERY_LOGGING=true
        ;;
    "${DIALOG_CANCEL}")
        # If they chose no,
        printf "  %b Query Logging off.\\n" "${INFO}"
        QUERY_LOGGING=false
        ;;
    "${DIALOG_ESC}")
        # User pressed <ESC>
        printf "  %b Escape pressed, exiting installer at Query Logging choice.%b\\n" "${COL_RED}" "${COL_NC}"
        exit 1
        ;;
    esac
}

# Allow the user to set their FTL privacy level
setPrivacyLevel() {
    # The default selection is level 0
    PRIVACY_LEVEL=$(dialog --no-shadow --keep-tite --output-fd 1 \
        --cancel-label "Exit" \
        --ok-label "Continue" \
        --radiolist "Select a privacy mode for FTL. https://docs.pi-hole.net/ftldns/privacylevels/" \
        "${r}" "${c}" 6 \
        "0" "Show everything" on \
        "1" "Hide domains" off \
        "2" "Hide domains and clients" off \
        "3" "Anonymous mode" off)

    result=$?
    case ${result} in
    "${DIALOG_OK}")
        printf "  %b Using privacy level: %s\\n" "${INFO}" "${PRIVACY_LEVEL}"
        ;;
    "${DIALOG_CANCEL}" | "${DIALOG_ESC}")
        printf "  %b Cancelled privacy level selection.%b\\n" "${COL_RED}" "${COL_NC}"
        exit 1
        ;;
    esac
}

# A function to display a list of example blocklists for users to select
chooseBlocklists() {
    # Back up any existing adlist file, on the off chance that it exists.
    if [[ -f "${adlistFile}" ]]; then
        mv "${adlistFile}" "${adlistFile}.old"
    fi
    # Let user select (or not) blocklists
    dialog --no-shadow --keep-tite \
        --backtitle "Pi-hole Installation" \
        --title "Blocklists" \
        --yesno "\\nPi-hole relies on third party lists in order to block ads.\
\\n\\nYou can use the suggestion below, and/or add your own after installation.\
\\n\\nSelect 'Yes' to include:\
\\n\\nStevenBlack's Unified Hosts List" \
        "${r}" "${c}" && result=0 || result=$?

    case ${result} in
    "${DIALOG_OK}")
        # If they chose yes,
        printf "  %b Installing StevenBlack's Unified Hosts List\\n" "${INFO}"
        echo "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" >>"${adlistFile}"
        ;;
    "${DIALOG_CANCEL}")
        # If they chose no,
        printf "  %b Not installing StevenBlack's Unified Hosts List\\n" "${INFO}"
        ;;
    "${DIALOG_ESC}")
        # User pressed <ESC>
        printf "  %b Escape pressed, exiting installer at blocklist choice.%b\\n" "${COL_RED}" "${COL_NC}"
        exit 1
        ;;
    esac
    # Create an empty adList file with appropriate permissions.
    if [ ! -f "${adlistFile}" ]; then
        install -m 644 /dev/null "${adlistFile}"
    else
        chmod 644 "${adlistFile}"
    fi
}

# Used only in unattended setup
# If there is already the adListFile, we keep it, else we create it using all default lists
installDefaultBlocklists() {
    # In unattended setup, could be useful to use userdefined blocklist.
    # If this file exists, we avoid overriding it.
    if [[ -f "${adlistFile}" ]]; then
        return
    fi
    echo "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" >>"${adlistFile}"
}

move_old_dnsmasq_ftl_configs() {
    # Create migration directory /etc/pihole/migration_backup_v6
    # and make it owned by pihole:pihole
    mkdir -p "${V6_CONF_MIGRATION_DIR}"
    chown pihole:pihole "${V6_CONF_MIGRATION_DIR}"

    # Move all conf files originally created by Pi-hole into this directory
    # - 01-pihole.conf
    # - 02-pihole-dhcp.conf
    # - 04-pihole-static-dhcp.conf
    # - 05-pihole-custom-cname.conf
    # - 06-rfc6761.conf
    mv /etc/dnsmasq.d/0{1,2,4,5}-pihole*.conf "${V6_CONF_MIGRATION_DIR}/" 2>/dev/null || true
    mv /etc/dnsmasq.d/06-rfc6761.conf "${V6_CONF_MIGRATION_DIR}/" 2>/dev/null || true

    # If the dnsmasq main config file exists
    local dnsmasq_conf="/etc/dnsmasq.conf"
    if [[ -f "${dnsmasq_conf}" ]]; then
        # There should not be anything custom in here for Pi-hole users
        # It is no longer needed, but we'll back it up instead of deleting it just in case
        mv "${dnsmasq_conf}" "${dnsmasq_conf}.old"
    fi

    # Create /etc/dnsmasq.d if it doesn't exist
    if [[ ! -d "/etc/dnsmasq.d" ]]; then
        mkdir "/etc/dnsmasq.d"
    fi
}

remove_old_pihole_lighttpd_configs() {
    local lighttpdConfig="/etc/lighttpd/lighttpd.conf"
    local condfd="/etc/lighttpd/conf.d/pihole-admin.conf"
    local confavailable="/etc/lighttpd/conf-available/15-pihole-admin.conf"
    local confenabled="/etc/lighttpd/conf-enabled/15-pihole-admin.conf"

    if [[ -f "${lighttpdConfig}" ]]; then
        sed -i '/include "\/etc\/lighttpd\/conf.d\/pihole-admin.conf"/d' "${lighttpdConfig}"
    fi

    if [[ -f "${condfd}" ]]; then
        rm "${condfd}"
    fi

    if is_command lighty-disable-mod; then
        lighty-disable-mod pihole-admin >/dev/null || true
    fi

    if [[ -f "${confenabled}" || -L "${confenabled}" ]]; then
        rm "${confenabled}"
    fi

    if [[ -f "${confavailable}" ]]; then
        rm "${confavailable}"
    fi
}

# Clean an existing installation to prepare for upgrade/reinstall
clean_existing() {
    # Local, named variables
    # ${1} Directory to clean
    local clean_directory="${1}"
    # Pop the first argument, and shift all addresses down by one (i.e. ${2} becomes ${1})
    shift
    # Then, we can access all arguments ($@) without including the directory to clean
    local old_files=("$@")

    # Remove each script in the old_files array
    for script in "${old_files[@]}"; do
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
        install -o "${USER}" -Dm755 -t "${PI_HOLE_BIN_DIR}" pihole
        install -Dm644 ./advanced/bash-completion/pihole /etc/bash_completion.d/pihole
        printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"

    else
        # Otherwise, show an error and exit
        printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
        printf "\\t\\t%bError: Local repo %s not found, exiting installer%b\\n" "${COL_RED}" "${PI_HOLE_LOCAL_REPO}" "${COL_NC}"
        return 1
    fi
}

# Install the configs from PI_HOLE_LOCAL_REPO to their various locations
installConfigs() {
    printf "\\n  %b Installing configs from %s...\\n" "${INFO}" "${PI_HOLE_LOCAL_REPO}"

    # Ensure that permissions are correctly set
    chown -R pihole:pihole /etc/pihole

    # Install empty custom.list file if it does not exist
    if [[ ! -r "${PI_HOLE_CONFIG_DIR}/hosts/custom.list" ]]; then
        if ! install -D -T -o pihole -g pihole -m 660 /dev/null "${PI_HOLE_CONFIG_DIR}/hosts/custom.list" &>/dev/null; then
            printf "  %b Error: Unable to initialize configuration file %s/custom.list\\n" "${COL_RED}" "${PI_HOLE_CONFIG_DIR}/hosts"
            return 1
        fi
    fi

    # Install pihole-FTL systemd or init.d service, based on whether systemd is the init system or not
    if ps -p 1 -o comm= | grep -q systemd; then
        install -T -m 0644 "${PI_HOLE_LOCAL_REPO}/advanced/Templates/pihole-FTL.systemd" '/etc/systemd/system/pihole-FTL.service'

        # Remove init.d service if present
        if [[ -e '/etc/init.d/pihole-FTL' ]]; then
            rm '/etc/init.d/pihole-FTL'
            update-rc.d pihole-FTL remove
        fi

        # Load final service
        systemctl daemon-reload
    else
        install -T -m 0755 "${PI_HOLE_LOCAL_REPO}/advanced/Templates/pihole-FTL.service" '/etc/init.d/pihole-FTL'
    fi
    install -T -m 0755 "${PI_HOLE_LOCAL_REPO}/advanced/Templates/pihole-FTL-prestart.sh" "${PI_HOLE_INSTALL_DIR}/pihole-FTL-prestart.sh"
    install -T -m 0755 "${PI_HOLE_LOCAL_REPO}/advanced/Templates/pihole-FTL-poststop.sh" "${PI_HOLE_INSTALL_DIR}/pihole-FTL-poststop.sh"
}

install_manpage() {
    # Copy Pi-hole man pages and call mandb to update man page database
    # Default location for man files for /usr/local/bin is /usr/local/share/man
    # on lightweight systems may not be present, so check before copying.
    printf "  %b Testing man page installation" "${INFO}"
    if ! is_command mandb; then
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
        install -d -m 755 /usr/local/share/man/man8
    fi
    if [[ ! -d "/usr/local/share/man/man5" ]]; then
        # if not present, create man5 directory
        install -d -m 755 /usr/local/share/man/man5
    fi
    # Testing complete, copy the files & update the man db
    install -D -m 644 -T ${PI_HOLE_LOCAL_REPO}/manpages/pihole.8 /usr/local/share/man/man8/pihole.8

    # remove previously installed man pages
    if [[ -f "/usr/local/share/man/man5/pihole-FTL.conf.5" ]]; then
        rm /usr/local/share/man/man5/pihole-FTL.conf.5
    fi
    if [[ -f "/usr/local/share/man/man8/pihole-FTL.8" ]]; then
        rm /usr/local/share/man/man8/pihole-FTL.8
    fi

    if mandb -q &>/dev/null; then
        # Updated successfully
        printf "%b  %b man pages installed and database updated\\n" "${OVER}" "${TICK}"
        return
    else
        # Something is wrong with the system's man installation, clean up
        # our files, (leave everything how we found it).
        rm /usr/local/share/man/man8/pihole.8
        printf "%b  %b man page db not updated, man pages not installed\\n" "${OVER}" "${CROSS}"
    fi
}

stop_service() {
    # Stop service passed in as argument.
    # Can softfail, as process may not be installed when this is called
    local str="Stopping ${1} service"
    printf "  %b %s..." "${INFO}" "${str}"
    if is_command systemctl; then
        systemctl -q stop "${1}" || true
    else
        service "${1}" stop >/dev/null || true
    fi
    printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
}

# Start/Restart service passed in as argument
restart_service() {
    # Local, named variables
    local str="Restarting ${1} service"
    printf "  %b %s..." "${INFO}" "${str}"
    # If systemctl exists,
    if is_command systemctl; then
        # use that to restart the service
        systemctl -q restart "${1}"
    else
        # Otherwise, fall back to the service command
        service "${1}" restart >/dev/null
    fi
    printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
}

# Enable service so that it will start with next reboot
enable_service() {
    # Local, named variables
    local str="Enabling ${1} service to start on reboot"
    printf "  %b %s..." "${INFO}" "${str}"
    # If systemctl exists,
    if is_command systemctl; then
        # use that to enable the service
        systemctl -q enable "${1}"
    else
        #  Otherwise, use update-rc.d to accomplish this
        update-rc.d "${1}" defaults >/dev/null
    fi
    printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
}

# Disable service so that it will not with next reboot
disable_service() {
    # Local, named variables
    local str="Disabling ${1} service"
    printf "  %b %s..." "${INFO}" "${str}"
    # If systemctl exists,
    if is_command systemctl; then
        # use that to disable the service
        systemctl -q disable "${1}"
    else
        # Otherwise, use update-rc.d to accomplish this
        update-rc.d "${1}" disable >/dev/null
    fi
    printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
}

check_service_active() {
    # If systemctl exists,
    if is_command systemctl; then
        # use that to check the status of the service
        systemctl -q is-enabled "${1}" 2>/dev/null
    else
        # Otherwise, fall back to service command
        service "${1}" status &>/dev/null
    fi
}

# Systemd-resolved's DNSStubListener and ftl can't share port 53.
disable_resolved_stublistener() {
    printf "  %b Testing if systemd-resolved is enabled\\n" "${INFO}"
    # Check if Systemd-resolved's DNSStubListener is enabled and active on port 53
    if check_service_active "systemd-resolved"; then
        # Disable the DNSStubListener to unbind it from port 53
        # Note that this breaks dns functionality on host until FTL is up and running
        printf "%b  %b Disabling systemd-resolved DNSStubListener\\n" "${OVER}" "${TICK}"
        mkdir -p /etc/systemd/resolved.conf.d
        cat > /etc/systemd/resolved.conf.d/90-pi-hole-disable-stub-listener.conf << EOF
[Resolve]
DNSStubListener=no
EOF
        systemctl reload-or-restart systemd-resolved
    else
        printf "%b  %b Systemd-resolved is not enabled\\n" "${OVER}" "${INFO}"
    fi
}

update_package_cache() {
    # Update package cache on apt based OSes. Do this every time since
    # it's quick and packages can be updated at any time.

    # Local, named variables
    local str="Update local cache of available packages"
    printf "  %b %s..." "${INFO}" "${str}"
    # Create a command from the package cache variable
    if eval "${UPDATE_PKG_CACHE}" &>/dev/null; then
        printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
    else
        # Otherwise, show an error and exit

        # In case we used apt-get and apt is also available, we use this as recommendation as we have seen it
        # gives more user-friendly (interactive) advice
        if [[ ${PKG_MANAGER} == "apt-get" ]] && is_command apt; then
            UPDATE_PKG_CACHE="apt update"
        fi
        printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
        printf "  %b Error: Unable to update package cache. Please try \"%s\"%b\\n" "${COL_RED}" "sudo ${UPDATE_PKG_CACHE}" "${COL_NC}"
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

    if [[ "${updatesToInstall}" -eq 0 ]]; then
        printf "%b  %b %s... up to date!\\n\\n" "${OVER}" "${TICK}" "${str}"
    else
        printf "%b  %b %s... %s updates available\\n" "${OVER}" "${TICK}" "${str}" "${updatesToInstall}"
        printf "  %b %bIt is recommended to update your OS after installing the Pi-hole!%b\\n\\n" "${INFO}" "${COL_GREEN}" "${COL_NC}"
    fi
}

install_dependent_packages() {
    # Install meta dependency package
    local str="Installing Pi-hole dependency package"
    printf "  %b %s..." "${INFO}" "${str}"

    # Install Debian/Ubuntu packages
    if is_command apt-get; then
        if [ -f /tmp/pihole-meta.deb ]; then
            if eval "${PKG_INSTALL}" "/tmp/pihole-meta.deb" &>/dev/null; then
                printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
                rm /tmp/pihole-meta.deb
            else
                printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
                printf "  %b Error: Unable to install Pi-hole dependency package.\\n" "${COL_RED}"
                return 1
            fi
        else
            printf "  %b Error: Unable to find Pi-hole dependency package.\\n" "${COL_RED}"
            return 1
        fi
    # Install Fedora/CentOS packages
    elif is_command rpm; then
        if [ -f /tmp/pihole-meta.rpm ]; then
            if eval "${PKG_INSTALL}" "/tmp/pihole-meta.rpm" &>/dev/null; then
                printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
                rm /tmp/pihole-meta.rpm
            else
                printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
                printf "  %b Error: Unable to install Pi-hole dependency package.\\n" "${COL_RED}"
                return 1
            fi
        else
            printf "  %b Error: Unable to find Pi-hole dependency package.\\n" "${COL_RED}"
            return 1
        fi

    # If neither apt-get or yum/dnf package managers were found
    else
        # we cannot install the dependency package
        printf "  %b No supported package manager found\\n" "${CROSS}"
        # so exit the installer
        exit 1
    fi

    printf "\\n"
    return 0
}

# Installs a cron file
installCron() {
    # Install the cron job
    local str="Installing latest Cron script"
    printf "\\n  %b %s..." "${INFO}" "${str}"
    # Copy the cron file over from the local repo
    # File must not be world or group writeable and must be owned by root
    install -D -m 644 -T -o root -g root ${PI_HOLE_LOCAL_REPO}/advanced/Templates/pihole.cron /etc/cron.d/pihole
    # Randomize gravity update time
    sed -i "s/59 1 /$((1 + RANDOM % 58)) $((3 + RANDOM % 2))/" /etc/cron.d/pihole
    # Randomize update checker time
    sed -i "s/59 17/$((1 + RANDOM % 58)) $((12 + RANDOM % 8))/" /etc/cron.d/pihole
    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
}

# Gravity is a very important script as it aggregates all of the domains into a single HOSTS formatted list,
# which is what Pi-hole needs to begin blocking ads
runGravity() {
    # Run gravity in the current shell as user pihole
    { sudo -u pihole bash /opt/pihole/gravity.sh --force; }
}

# Check if the pihole user exists and create if it does not
create_pihole_user() {
    local str="Checking for user 'pihole'"
    printf "  %b %s..." "${INFO}" "${str}"
    # If the pihole user exists,
    if id -u pihole &>/dev/null; then
        # and if the pihole group exists,
        if getent group pihole >/dev/null 2>&1; then
            # succeed
            printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
        else
            local str="Checking for group 'pihole'"
            printf "  %b %s..." "${INFO}" "${str}"
            local str="Creating group 'pihole'"
            # if group can be created
            if groupadd pihole; then
                printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
                local str="Adding user 'pihole' to group 'pihole'"
                printf "  %b %s..." "${INFO}" "${str}"
                # if pihole user can be added to group pihole
                if usermod -g pihole pihole; then
                    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
                else
                    printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
                fi
            else
                printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
            fi
        fi
    else
        # If the pihole user doesn't exist,
        printf "%b  %b %s" "${OVER}" "${CROSS}" "${str}"
        local str="Checking for group 'pihole'"
        printf "  %b %s..." "${INFO}" "${str}"
        if getent group pihole >/dev/null 2>&1; then
            # group pihole exists
            printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
            # then create and add her to the pihole group
            local str="Creating user 'pihole'"
            printf "%b  %b %s..." "${OVER}" "${INFO}" "${str}"
            if useradd -r --no-user-group -g pihole -s /usr/sbin/nologin pihole; then
                printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
            else
                printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
            fi
        else
            # group pihole does not exist
            printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
            local str="Creating group 'pihole'"
            # if group can be created
            if groupadd pihole; then
                printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
                # create and add pihole user to the pihole group
                local str="Creating user 'pihole'"
                printf "%b  %b %s..." "${OVER}" "${INFO}" "${str}"
                if useradd -r --no-user-group -g pihole -s /usr/sbin/nologin pihole; then
                    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
                else
                    printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
                fi

            else
                printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
            fi
        fi
    fi
}

# Install the logrotate script
installLogrotate() {
    local str="Installing latest logrotate script"
    local target=/etc/pihole/logrotate
    local logfileUpdate=false

    printf "\\n  %b %s..." "${INFO}" "${str}"
    if [[ -f ${target} ]]; then

        # Account for changed logfile paths from /var/log -> /var/log/pihole/ made in core v5.11.
        if grep -q "/var/log/pihole.log" ${target} || grep -q "/var/log/pihole-FTL.log" ${target}; then
            sed -i 's/\/var\/log\/pihole.log/\/var\/log\/pihole\/pihole.log/g' ${target}
            sed -i 's/\/var\/log\/pihole-FTL.log/\/var\/log\/pihole\/FTL.log/g' ${target}

            printf "\\n\\t%b Old log file paths updated in existing logrotate file. \\n" "${INFO}"
            logfileUpdate=true
        fi

        # Account for added webserver.log in v6.0
        if ! grep -q "/var/log/pihole/webserver.log" ${target}; then
            echo "/var/log/pihole/webserver.log {
# su #
weekly
copytruncate
rotate 3
compress
delaycompress
notifempty
nomail
}" >> ${target}

            printf "\\n\\t%b webserver.log added to logrotate file. \\n" "${INFO}"
            logfileUpdate=true
        fi
        if [[ "${logfileUpdate}" == false ]]; then
            printf "\\n\\t%b Existing logrotate file found. No changes made.\\n" "${INFO}"
            return
        fi
    else
        # Copy the file over from the local repo
        # Logrotate config file must be owned by root and not writable by group or other
        install -o root -g root -D -m 644 -T "${PI_HOLE_LOCAL_REPO}"/advanced/Templates/logrotate ${target}
    fi

    # Different operating systems have different user / group
    # settings for logrotate that makes it impossible to create
    # a static logrotate file that will work with e.g.
    # Rasbian and Ubuntu at the same time. Hence, we have to
    # customize the logrotate script here in order to reflect
    # the local properties of the /var/log directory
    logusergroup="$(stat -c '%U %G' /var/log)"
    # If there is a usergroup for log rotation,
    if [[ -n "${logusergroup}" ]]; then
        # replace the line in the logrotate script with that usergroup.
        sed -i "s/# su #/su ${logusergroup}/g;" ${target}
    fi
    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
}

# Install base files and web interface
installPihole() {
    # Install base files and web interface
    if ! installScripts; then
        printf "  %b Failure in dependent script copy function.\\n" "${CROSS}"
        exit 1
    fi

    # Move old dnsmasq files to $V6_CONF_MIGRATION_DIR for later migration via migrate_dnsmasq_configs()
    move_old_dnsmasq_ftl_configs
    remove_old_pihole_lighttpd_configs

    # Install config files
    if ! installConfigs; then
        printf "  %b Failure in dependent config copy function.\\n" "${CROSS}"
        exit 1
    fi

    # Install the cron file
    installCron

    # Install the logrotate file
    installLogrotate || true

    # install a man page entry for pihole
    install_manpage
}

# SELinux
checkSelinux() {
    local DEFAULT_SELINUX
    local CURRENT_SELINUX
    local SELINUX_ENFORCING=0
    # Check for SELinux configuration file and getenforce command
    if [[ -f /etc/selinux/config ]] && is_command getenforce; then
        # Check the default SELinux mode
        DEFAULT_SELINUX=$(awk -F= '/^SELINUX=/ {print $2}' /etc/selinux/config)
        case "${DEFAULT_SELINUX,,}" in
        enforcing)
            printf "  %b %bDefault SELinux: %s%b\\n" "${CROSS}" "${COL_RED}" "${DEFAULT_SELINUX,,}" "${COL_NC}"
            SELINUX_ENFORCING=1
            ;;
        *) # 'permissive' and 'disabled'
            printf "  %b %bDefault SELinux: %s%b\\n" "${TICK}" "${COL_GREEN}" "${DEFAULT_SELINUX,,}" "${COL_NC}"
            ;;
        esac
        # Check the current state of SELinux
        CURRENT_SELINUX=$(getenforce)
        case "${CURRENT_SELINUX,,}" in
        enforcing)
            printf "  %b %bCurrent SELinux: %s%b\\n" "${CROSS}" "${COL_RED}" "${CURRENT_SELINUX,,}" "${COL_NC}"
            SELINUX_ENFORCING=1
            ;;
        *) # 'permissive' and 'disabled'
            printf "  %b %bCurrent SELinux: %s%b\\n" "${TICK}" "${COL_GREEN}" "${CURRENT_SELINUX,,}" "${COL_NC}"
            ;;
        esac
    else
        echo -e "  ${INFO} ${COL_GREEN}SELinux not detected${COL_NC}"
    fi
    # Exit the installer if any SELinux checks toggled the flag
    if [[ "${SELINUX_ENFORCING}" -eq 1 ]] && [[ -z "${PIHOLE_SELINUX}" ]]; then
        printf "  Pi-hole does not provide an SELinux policy as the required changes modify the security of your system.\\n"
        printf "  Please refer to https://wiki.centos.org/HowTos/SELinux if SELinux is required for your deployment.\\n"
        printf "      This check can be skipped by setting the environment variable %bPIHOLE_SELINUX%b to %btrue%b\\n" "${COL_RED}" "${COL_NC}" "${COL_RED}" "${COL_NC}"
        printf "      e.g: export PIHOLE_SELINUX=true\\n"
        printf "      By setting this variable to true you acknowledge there may be issues with Pi-hole during or after the install\\n"
        printf "\\n  %bSELinux Enforcing detected, exiting installer%b\\n" "${COL_RED}" "${COL_NC}"
        exit 1
    elif [[ "${SELINUX_ENFORCING}" -eq 1 ]] && [[ -n "${PIHOLE_SELINUX}" ]]; then
        printf "  %b %bSELinux Enforcing detected%b. PIHOLE_SELINUX env variable set - installer will continue\\n" "${INFO}" "${COL_RED}" "${COL_NC}"
    fi
}

check_download_exists() {
    # Check if the download exists and we can reach the server
    local status
    status=$(curl --head --silent "https://ftl.pi-hole.net/${1}" | head -n 1)

    # Check the status code
    if grep -q "200" <<<"$status"; then
        return 0
    elif grep -q "404" <<<"$status"; then
        return 1
    fi

    # Other error or no status code at all, e.g., no Internet, server not
    # available/reachable, ...
    return 2
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
    output=$({ git ls-remote --heads --quiet | cut -d'/' -f3- -; } 2>&1)
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
    git stash --all --quiet &>/dev/null || true
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
    # Data in the repositories is public anyway so we can make it readable by everyone (+r to keep executable permission if already set by git)
    chmod -R a+rX "${directory}"

    git_pull=$(git pull --no-rebase || return 1)

    printf "  %b %s\\n" "${INFO}" "${git_pull}"

    return 0
}

clone_or_reset_repos() {
    # If the user wants to repair/update,
    if [[ "${repair}" == true ]]; then
        printf "  %b Resetting local repos\\n" "${INFO}"
        # Reset the Core repo
        resetRepo ${PI_HOLE_LOCAL_REPO} ||
            {
                printf "  %b Unable to reset %s, exiting installer%b\\n" "${COL_RED}" "${PI_HOLE_LOCAL_REPO}" "${COL_NC}"
                exit 1
            }
        # Reset the Web repo
        resetRepo ${webInterfaceDir} ||
            {
                printf "  %b Unable to reset %s, exiting installer%b\\n" "${COL_RED}" "${webInterfaceDir}" "${COL_NC}"
                exit 1
            }
    # Otherwise, a fresh installation is happening
    else
        # so get git files for Core
        getGitFiles ${PI_HOLE_LOCAL_REPO} ${piholeGitUrl} ||
            {
                printf "  %b Unable to clone %s into %s, unable to continue%b\\n" "${COL_RED}" "${piholeGitUrl}" "${PI_HOLE_LOCAL_REPO}" "${COL_NC}"
                exit 1
            }
        # get the Web git files
        getGitFiles ${webInterfaceDir} ${webInterfaceGitUrl} ||
            {
                printf "  %b Unable to clone %s into ${webInterfaceDir}, exiting installer%b\\n" "${COL_RED}" "${webInterfaceGitUrl}" "${COL_NC}"
                exit 1
            }
    fi
}

# Download FTL binary to random temp directory and install FTL binary
# Disable directive for SC2120 a value _can_ be passed to this function, but it is passed from an external script that sources this one
FTLinstall() {
    # Local, named variables
    local str="Downloading and Installing FTL"
    printf "  %b %s..." "${INFO}" "${str}"

    # Move into the temp ftl directory
    pushd "$(mktemp -d)" >/dev/null || {
        printf "Unable to make temporary directory for FTL binary download\\n"
        return 1
    }
    local tempdir
    tempdir="$(pwd)"
    local ftlBranch
    local url

    if [[ -f "/etc/pihole/ftlbranch" ]]; then
        ftlBranch=$(</etc/pihole/ftlbranch)
    else
        ftlBranch="master"
    fi

    local binary
    binary="${1}"

    # Determine which version of FTL to download
    if [[ "${ftlBranch}" == "master" ]]; then
        url="https://github.com/pi-hole/ftl/releases/latest/download"
    else
        url="https://ftl.pi-hole.net/${ftlBranch}"
    fi

    if curl -sSL --fail "${url}/${binary}" -o "${binary}"; then
        # If the download worked, get sha1 of the binary we just downloaded for verification.
        curl -sSL --fail "${url}/${binary}.sha1" -o "${binary}.sha1"

        # If we downloaded binary file (as opposed to text),
        if sha1sum --status --quiet -c "${binary}".sha1; then
            printf "transferred... "

            # Before stopping FTL, we download the macvendor database
            curl -sSL "https://ftl.pi-hole.net/macvendor.db" -o "${PI_HOLE_CONFIG_DIR}/macvendor.db" || true

            # Stop pihole-FTL service if available
            stop_service pihole-FTL >/dev/null

            # Install the new version with the correct permissions
            install -T -m 0755 "${binary}" /usr/bin/pihole-FTL

            # Move back into the original directory the user was in
            popd >/dev/null || {
                printf "Unable to return to original directory after FTL binary download.\\n"
                return 1
            }

            # Installed the FTL service
            printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"

            # Remove temp dir
            remove_dir "${tempdir}"

            return 0
        else
            # Otherwise, the hash download failed, so print and exit.
            popd >/dev/null || {
                printf "Unable to return to original directory after FTL binary download.\\n"
                return 1
            }
            printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
            printf "  %b Error: Download of %s/%s failed (checksum error)%b\\n" "${COL_RED}" "${url}" "${binary}" "${COL_NC}"

            # Remove temp dir
            remove_dir "${tempdir}"
            return 1
        fi
    else
        # Otherwise, the download failed, so print and exit.
        popd >/dev/null || {
            printf "Unable to return to original directory after FTL binary download.\\n"
            return 1
        }
        printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
        # The URL could not be found
        printf "  %b Error: URL %s/%s not found%b\\n" "${COL_RED}" "${url}" "${binary}" "${COL_NC}"

        # Remove temp dir
        remove_dir "${tempdir}"
        return 1
    fi
}

remove_dir() {
    # Delete dir
    rm -r "${1}" >/dev/null 2>&1 ||
        echo -e "  ${CROSS} Unable to remove ${1}"
}

get_binary_name() {
    local l_binary
    local machine
    machine=$(uname -m)

    local str="Detecting processor"
    printf "  %b %s..." "${INFO}" "${str}"

    # If the machine is aarch64 (armv8)
    if [[ "${machine}" == "aarch64" ]]; then
        # If AArch64 is found (e.g., BCM2711 in Raspberry Pi 4)
        printf "%b  %b Detected AArch64 (64 Bit ARM) architecture\\n" "${OVER}" "${TICK}"
        l_binary="pihole-FTL-arm64"
    elif [[ "${machine}" == "arm"* ]]; then
        # ARM 32 bit
        # Get supported processor from other binaries installed on the system
        # We cannot really rely on the output of $(uname -m) above as this may
        # return an incorrect architecture when buildx-compiling with QEMU
        local cpu_arch
        cpu_arch=$(readelf -A "$(command -v sh)" | grep Tag_CPU_arch | awk '{ print $2 }')

        # Get the revision from the CPU architecture
        local rev
        rev=$(echo "${cpu_arch}" | grep -o '[0-9]*')
        if [[ "${rev}" -eq 6 ]]; then
            # If ARMv6 is found (e.g., BCM2835 in Raspberry Pi 1 and Zero)
            printf "%b  %b Detected ARMv6 architecture\\n" "${OVER}" "${TICK}"
            l_binary="pihole-FTL-armv6"
        elif [[ "${rev}" -ge 7 ]]; then
            # If ARMv7 or higher is found (e.g., BCM2836 in Raspberry PI 2 Mod. B)
            # This path is also used for ARMv8 when the OS is in 32bit mode
            # (e.g., BCM2837 in Raspberry Pi Model 3B, or BCM2711 in Raspberry Pi 4)
            printf "%b  %b Detected ARMv7 (or newer) architecture (%s)\\n" "${OVER}" "${TICK}" "${cpu_arch}"
            l_binary="pihole-FTL-armv7"
        else
            # Otherwise, Pi-hole does not support this architecture
            printf "%b  %b This processor architecture is not supported by Pi-hole (%s)\\n" "${OVER}" "${CROSS}" "${cpu_arch}"
            l_binary=""
        fi
    elif [[ "${machine}" == "x86_64" ]]; then
        # This gives the processor of packages dpkg installs (for example, "i386")
        local dpkgarch
        dpkgarch=$(dpkg --print-processor 2>/dev/null || dpkg --print-architecture 2>/dev/null)

        # Special case: This is a 32 bit OS, installed on a 64 bit machine
        # -> change machine processor to download the 32 bit executable
        # We only check this for Debian-based systems as this has been an issue
        # in the past (see https://github.com/pi-hole/pi-hole/pull/2004)
        if [[ "${dpkgarch}" == "i386" ]]; then
            printf "%b  %b Detected 32bit (i686) architecture\\n" "${OVER}" "${TICK}"
            l_binary="pihole-FTL-386"
        else
            # 64bit OS
            printf "%b  %b Detected x86_64 architecture\\n" "${OVER}" "${TICK}"
            l_binary="pihole-FTL-amd64"
        fi
    elif [[ "${machine}" == "riscv64" ]]; then
        printf "%b  %b Detected riscv64 architecture\\n" "${OVER}" "${TICK}"
        l_binary="pihole-FTL-riscv64"
    else
        # Something else - we try to use 32bit executable and warn the user
        if [[ ! "${machine}" == "i686" ]]; then
            printf "%b  %b %s...\\n" "${OVER}" "${CROSS}" "${str}"
            printf "  %b %bNot able to detect architecture (unknown: %s), trying x86 (32bit) executable%b\\n" "${INFO}" "${COL_RED}" "${machine}" "${COL_NC}"
            printf "  %b Contact Pi-hole Support if you experience issues (e.g: FTL not running)\\n" "${INFO}"
        else
            printf "%b  %b Detected 32bit (i686) architecture\\n" "${OVER}" "${TICK}"
        fi
        l_binary="pihole-FTL-386"
    fi

    # Returning a string value via echo
    echo ${l_binary}
}

FTLcheckUpdate() {
    # In the next section we check to see if FTL is already installed (in case of pihole -r).
    # If the installed version matches the latest version, then check the installed sha1sum of the binary vs the remote sha1sum. If they do not match, then download
    local ftlLoc
    ftlLoc=$(command -v pihole-FTL 2>/dev/null)

    local ftlBranch

    if [[ -f "/etc/pihole/ftlbranch" ]]; then
        ftlBranch=$(</etc/pihole/ftlbranch)
    else
        ftlBranch="master"
    fi

    local binary
    binary="${1}"

    local remoteSha1
    local localSha1

    if [[ ! "${ftlBranch}" == "master" ]]; then
        # This is not the master branch
        local path
        path="${ftlBranch}/${binary}"

        # Check whether or not the binary for this FTL branch actually exists. If not, then there is no update!
        local status
        if ! check_download_exists "$path"; then
            status=$?
            if [ "${status}" -eq 1 ]; then
                printf "  %b Branch \"%s\" is not available.\\n" "${INFO}" "${ftlBranch}"
                printf "  %b Use %bpihole checkout ftl [branchname]%b to switch to a valid branch.\\n" "${INFO}" "${COL_GREEN}" "${COL_NC}"
            elif [ "${status}" -eq 2 ]; then
                printf "  %b Unable to download from ftl.pi-hole.net. Please check your Internet connection and try again later.\\n" "${CROSS}"
                return 3
            else
                printf "  %b Unknown error. Please contact Pi-hole Support\\n" "${CROSS}"
                return 4
            fi
        fi

        if [[ ${ftlLoc} ]]; then
            # We already have a pihole-FTL binary installed, check if it's the
            # same as the remote one
            # Alt branches don't have a tagged version against them, so just
            # confirm the checksum of the local vs remote to decide whether we
            # download or not
            printf "  %b FTL binary already installed, verifying integrity...\\n" "${INFO}"
            checkSumFile="https://ftl.pi-hole.net/${ftlBranch}/${binary}.sha1"
            # Continue further down...
        else
            return 0
        fi
    else
        # This is the master branch
        if [[ ${ftlLoc} ]]; then
            # We already have a pihole-FTL binary installed, check if it's the
            # same as the remote one
            local FTLversion
            FTLversion=$(/usr/bin/pihole-FTL tag)

            # Get the latest version from the GitHub API
            local FTLlatesttag
            FTLlatesttag=$(curl -s https://api.github.com/repos/pi-hole/FTL/releases/latest | jq -sRr 'fromjson? | .tag_name | values')

            if [ -z "${FTLlatesttag}" ]; then
                # There was an issue while retrieving the latest version
                printf "  %b Failed to retrieve latest FTL release metadata\\n" "${CROSS}"
                return 3
            fi

            # Check if the installed version matches the latest version
            if [[ "${FTLversion}" != "${FTLlatesttag}" ]]; then
                # If the installed version does not match the latest version,
                # then download
                return 0
            else
                # If the installed version matches the latest version, then
                # check the installed sha1sum of the binary vs the remote
                # sha1sum. If they do not match, then download
                printf "  %b Latest FTL binary already installed (%s), verifying integrity...\\n" "${INFO}" "${FTLlatesttag}"
                checkSumFile="https://github.com/pi-hole/FTL/releases/download/${FTLversion%$'\r'}/${binary}.sha1"
                # Continue further down...
            fi
        else
            # FTL not installed, then download
            return 0
        fi
    fi

    # If we reach this point, we need to check the checksum of the local vs
    # remote to decide whether we download or not
    remoteSha1=$(curl -sSL --fail "${checkSumFile}" | cut -d ' ' -f 1)
    localSha1=$(sha1sum "${ftlLoc}" | cut -d ' ' -f 1)

    # Check we downloaded a valid checksum (no 404 or other error like
    # no DNS resolution)
    if [[ ! "${remoteSha1}" =~ ^[a-f0-9]{40}$ ]]; then
        printf "  %b Remote checksum not available, trying to redownload...\\n" "${CROSS}"
        return 0
    elif [[ "${remoteSha1}" != "${localSha1}" ]]; then
        printf "  %b Remote binary is different, downloading...\\n" "${CROSS}"
        return 0
    fi

    printf "  %b Local binary up-to-date. No need to download!\\n" "${INFO}"
    return 1
}

# Detect suitable FTL binary platform
FTLdetect() {
    printf "\\n  %b FTL Checks...\\n\\n" "${INFO}"

    printf "  %b" "${2}"

    if FTLcheckUpdate "${1}"; then
        FTLinstall "${1}" || return 1
    else
        case $? in
            1) :;; # FTL is up-to-date
            *) exit 1;; # 404 (2), other HTTP or curl error (3), unknown (4)
        esac
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
    sed 's/\[[0-9;]\{1,5\}m//g' </proc/$$/fd/3 >"${installLogLoc}"
    chmod 644 "${installLogLoc}"
    chown pihole:pihole "${installLogLoc}"
}

disableLighttpd() {
    # Return early when lighttpd is not active
    if ! check_service_active lighttpd; then
        return
    fi

    local response
    # Detect if the terminal is interactive
    if [[ -t 0 ]]; then
        # The terminal is interactive
        dialog --no-shadow --keep-tite \
            --title "Pi-hole v6.0 no longer uses lighttpd" \
           --yesno "\\n\\nPi-hole v6.0 has its own embedded web server so lighttpd is no longer needed *unless* you have custom configurations.\\n\\nIn this case, you can opt-out of disabling lighttpd and pihole-FTL will try to bind to an alternative port such as 8080.\\n\\nDo you want to disable lighttpd (recommended)?" "${r}" "${c}" && response=0 || response="$?"
    else
        # The terminal is non-interactive, assume yes. Lighttpd will be stopped
        # but keeps being installed and can easily be re-enabled by the user
        response=0
    fi

    # If the user does not want to disable lighttpd, return early
    if [[ "${response}" -ne 0 ]]; then
        return
    fi

    # Lighttpd is not needed anymore, so disable it
    # We keep all the configuration files in place, so the user can re-enable it
    # if needed

    # Check if lighttpd is installed
    if is_command lighttpd; then
        # Stop the lighttpd service
        stop_service lighttpd

        # Disable the lighttpd service
        disable_service lighttpd
    fi
}

migrate_dnsmasq_configs() {
    # Previously, Pi-hole created a number of files in /etc/dnsmasq.d
    # During migration, their content is copied into the new single source of
    # truth file /etc/pihole/pihole.toml and the old files are moved away to
    # avoid conflicts with other services on this system

    # Exit early if this is already Pi-hole v6.0
    # We decide this on the non-existence of the file /etc/pihole/setupVars.conf (either moved by previous migration or fresh install)
    if [[ ! -f "/etc/pihole/setupVars.conf" ]]; then
        return 0
    fi

    # Disable lighttpd server during v6 migration
    disableLighttpd

    # move_old_dnsmasq_ftl_configs() moved everything is in place,
    # so we can create the new config file /etc/pihole/pihole.toml
    # This file will be created with the default settings unless the user has
    # changed settings via setupVars.conf or the other dnsmasq files moved before
    # During migration, setupVars.conf is moved to /etc/pihole/migration_backup_v6
    str="Migrating Pi-hole configuration to version 6"
    printf "  %b %s..." "${INFO}" "${str}"
    local FTLoutput FTLstatus
    FTLoutput=$(pihole-FTL migrate v6)
    FTLstatus=$?
    if [[ "${FTLstatus}" -eq 0 ]]; then
        printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
    else
        printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
    fi

    # Print the output of the FTL migration prefacing every line with four
    # spaces for alignment
    printf "%b" "${FTLoutput}" | sed 's/^/    /'

    # Print a blank line for separation
    printf "\\n"
}

# Check for availability of either the "service" or "systemctl" commands
check_service_command() {
    # Check for the availability of the "service" command
    if ! is_command service && ! is_command systemctl; then
        # If neither the "service" nor the "systemctl" command is available, inform the user
        printf "  %b Neither the service nor the systemctl commands are available\\n" "${CROSS}"
        printf "      on this machine. This Pi-hole installer cannot continue.\\n"
        exit 1
    fi
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
    else
        # Otherwise, they do not have enough privileges, so let the user know
        printf "  %b %s\\n" "${INFO}" "${str}"
        printf "  %b %bScript called with non-root privileges%b\\n" "${INFO}" "${COL_RED}" "${COL_NC}"
        printf "      The Pi-hole requires elevated privileges to install and run\\n"
        printf "      Please check the installer for any concerns regarding this requirement\\n"
        printf "      Make sure to download this script from a trusted source\\n\\n"
        printf "  %b Sudo utility check" "${INFO}"

        # If the sudo command exists, try rerunning as admin
        if is_command sudo; then
            printf "%b  %b Sudo utility check\\n" "${OVER}" "${TICK}"

            # when run via curl piping
            if [[ "$0" == "bash" ]]; then
                # Download the install script and run it with admin rights
                exec curl -sSL https://install.pi-hole.net | sudo bash "$@"
            else
                # when run via calling local bash script
                exec sudo bash "$0" "$@"
            fi

            exit $?
        else
            # Otherwise, tell the user they need to run the script as root, and bail
            printf "%b  %b Sudo utility check\\n" "${OVER}" "${CROSS}"
            printf "  %b Sudo is needed for the Web Interface to run pihole commands\\n\\n" "${INFO}"
            printf "  %b %bPlease re-run this installer as root${COL_NC}\\n" "${INFO}" "${COL_RED}"
            exit 1
        fi
    fi

    # Check if SELinux is Enforcing and exit before doing anything else
    checkSelinux

    # Check for availability of either the "service" or "systemctl" commands
    check_service_command

    # Check if this is a fresh install or an update/repair
    check_fresh_install

    # Check for supported package managers so that we may install dependencies
    package_manager_detect

    # Update package cache only on apt based systems
    if is_command apt-get; then
            update_package_cache || exit 1
    fi

    # Notify user of package availability
    notify_package_updates_available

    # Build dependency package
    build_dependency_package

    # Install Pi-hole dependencies
    install_dependent_packages


    # Check if there is a usable FTL binary available on this architecture - do
    # this early on as FTL is a hard dependency for Pi-hole
    local funcOutput
    funcOutput=$(get_binary_name) #Store output of get_binary_name here
    # Abort early if this processor is not supported (get_binary_name returns empty string)
    if [[ "${funcOutput}" == "" ]]; then
        printf "  %b Upgrade/install aborted\\n" "${CROSS}" "${DISTRO_NAME}"
        exit 1
    fi

    if [[ "${fresh_install}" == false ]]; then
        # if it's running unattended,
        if [[ "${runUnattended}" == true ]]; then
            printf "  %b Performing unattended setup, no dialogs will be displayed\\n" "${INFO}"
            # also disable debconf-apt-progress dialogs
            export DEBIAN_FRONTEND="noninteractive"
        fi
    fi

    if [[ "${fresh_install}" == true ]]; then
        # Display welcome dialogs
        welcomeDialogs
        # Create directory for Pi-hole storage (/etc/pihole/)
        install -d -m 755 "${PI_HOLE_CONFIG_DIR}"
        # Determine available interfaces
        get_available_interfaces
        # Find interfaces and let the user choose one
        chooseInterface
        # find IPv4 and IPv6 information of the device
        collect_v4andv6_information
        # Decide what upstream DNS Servers to use
        setDNS
        # Give the user a choice of blocklists to include in their install. Or not.
        chooseBlocklists
        # Let the user decide if they want query logging enabled...
        setLogging
        # Let the user decide the FTL privacy level
        setPrivacyLevel
    else
        # Setup adlist file if not exists
        installDefaultBlocklists
    fi
    # Download or reset the appropriate git repos depending on the 'repair' flag
    clone_or_reset_repos

    # Create the pihole user
    create_pihole_user

    # Download and install FTL
    local binary
    binary="pihole-FTL${funcOutput##*pihole-FTL}" #binary name will be the last line of the output of get_binary_name (it always begins with pihole-FTL)
    local theRest
    theRest="${funcOutput%pihole-FTL*}" # Print the rest of get_binary_name's output to display (cut out from first instance of "pihole-FTL")
    if ! FTLdetect "${binary}" "${theRest}"; then
        printf "  %b FTL Engine not installed\\n" "${CROSS}"
        exit 1
    fi

    # Install and log everything to a file
    installPihole | tee -a /proc/$$/fd/3

    # /opt/pihole/utils.sh should be installed by installScripts now, so we can use it
    if [ -f "${PI_HOLE_INSTALL_DIR}/utils.sh" ]; then
        # shellcheck source="./advanced/Scripts/utils.sh"
        source "${PI_HOLE_INSTALL_DIR}/utils.sh"
    else
        printf "  %b Failure: /opt/pihole/utils.sh does not exist .\\n" "${CROSS}"
        exit 1
    fi

    # Copy the temp log file into final log location for storage
    copy_to_install_log

    # Migrate existing install to v6.0
    migrate_dnsmasq_configs

    # Cleanup old v5 sudoers file if it exists
    sudoers_file="/etc/sudoers.d/pihole"
    if [[ -f "${sudoers_file}" ]]; then
        # only remove the file if it contains the Pi-hole header
        if grep -q "Pi-hole: A black hole for Internet advertisements" "${sudoers_file}"; then
            rm -f "${sudoers_file}"
        fi
    fi

    # Check for and disable systemd-resolved-DNSStubListener before reloading resolved
    # DNSStubListener needs to remain in place for installer to download needed files,
    # so this change needs to be made after installation is complete,
    # but before starting or resttarting the ftl service
    disable_resolved_stublistener

    if [[ "${fresh_install}" == false ]]; then
        # Check if gravity database needs to be upgraded. If so, do it without rebuilding
        # gravity altogether. This may be a very long running task needlessly blocking
        # the update process.
        # Only do this on updates, not on fresh installs as the database does not exit yet
        /opt/pihole/gravity.sh --upgrade
    fi

    printf "  %b Restarting services...\\n" "${INFO}"
    # Start services

    # Enable FTL
    # Ensure the service is enabled before trying to start it
    # Fixes a problem reported on Ubuntu 18.04 where trying to start
    # the service before enabling causes installer to exit
    enable_service pihole-FTL

    restart_service pihole-FTL

    if [[ "${fresh_install}" == true ]]; then
        # apply settings to pihole.toml
        # needs to be done after FTL service has been started, otherwise pihole.toml does not exist
        # set on fresh installations by setDNS() and setPrivacyLevel() and setLogging()

        # Upstreams may be needed in order to run gravity.sh
        if [ -n "${PIHOLE_DNS_1}" ]; then
            local string="\"${PIHOLE_DNS_1}\""
            [ -n "${PIHOLE_DNS_2}" ] && string+=", \"${PIHOLE_DNS_2}\""
            setFTLConfigValue "dns.upstreams" "[ $string ]"
        fi

        if [ -n "${QUERY_LOGGING}" ]; then
            setFTLConfigValue "dns.queryLogging" "${QUERY_LOGGING}"
        fi

        if [ -n "${PRIVACY_LEVEL}" ]; then
            setFTLConfigValue "misc.privacylevel" "${PRIVACY_LEVEL}"
        fi

        if [ -n "${PIHOLE_INTERFACE}" ]; then
            setFTLConfigValue "dns.interface" "${PIHOLE_INTERFACE}"
        fi
    fi

    # Download and compile the aggregated block list
    runGravity

    # Update local and remote versions via updatechecker
    /opt/pihole/updatecheck.sh

    if [[ "${fresh_install}" == true ]]; then

        # Get the Web interface port, return only the first port and strip all non-numeric characters
        WEBPORT=$(getFTLConfigValue webserver.port|cut -d, -f1 | tr -cd '0-9')

        # If this is a fresh install, we will set a random password.
        # Users can change this password after installation if they wish
        pw=$(tr -dc _A-Z-a-z-0-9 </dev/urandom | head -c 8)
        pihole setpassword "${pw}" > /dev/null

        # Explain to the user how to use Pi-hole as their DNS server
        printf "\\n  %b You may now configure your devices to use the Pi-hole as their DNS server\\n" "${INFO}"
        [[ -n "${IPV4_ADDRESS%/*}" ]] && printf "  %b Pi-hole DNS (IPv4): %s\\n" "${INFO}" "${IPV4_ADDRESS%/*}"
        [[ -n "${IPV6_ADDRESS}" ]] && printf "  %b Pi-hole DNS (IPv6): %s\\n" "${INFO}" "${IPV6_ADDRESS}"
        printf "  %b If you have not done so already, the above IP should be set to static.\\n" "${INFO}"

        printf "  %b View the web interface at http://pi.hole:${WEBPORT}/admin or http://%s/admin\\n\\n" "${INFO}" "${IPV4_ADDRESS%/*}:${WEBPORT}"
        printf "  %b Web Interface password: %b%s%b\\n" "${INFO}" "${COL_GREEN}" "${pw}" "${COL_NC}"
        printf "  %b This can be changed using 'pihole setpassword'\\n\\n" "${INFO}"
        printf "  %b To allow your user to use all CLI functions without authentication, refer to\\n" "${INFO}"
        printf "    our documentation at: https://docs.pi-hole.net/main/post-install/\\n\\n"

        # Final dialog message to the user
        dialog --no-shadow --keep-tite \
            --title "Installation Complete!" \
            --msgbox "Configure your devices to use the Pi-hole as their DNS server using:\
\\n\\nIPv4:	${IPV4_ADDRESS%/*}\
\\nIPv6:	${IPV6_ADDRESS:-"Not Configured"}\
\\nIf you have not done so already, the above IP should be set to static.\
\\nView the web interface at http://pi.hole/admin:${WEBPORT} or http://${IPV4_ADDRESS%/*}:${WEBPORT}/admin\\n\\nYour Admin Webpage login password is ${pw}\
\\n
\\n
\\nTo allow your user to use all CLI functions without authentication,\
\\nrefer to https://docs.pi-hole.net/main/post-install/" "${r}" "${c}"

        INSTALL_TYPE="Installation"
    else
        INSTALL_TYPE="Update"
    fi

    # Display where the log file is
    printf "\\n  %b The install log is located at: %s\\n" "${INFO}" "${installLogLoc}"
    printf "  %b %b%s complete! %b\\n" "${TICK}" "${COL_GREEN}" "${INSTALL_TYPE}" "${COL_NC}"

    if [[ "${INSTALL_TYPE}" == "Update" ]]; then
        printf "\\n"
        "${PI_HOLE_BIN_DIR}"/pihole version
    fi
}

# allow to source this script without running it
if [[ "${SKIP_INSTALL}" != true ]]; then
    main "$@"
fi
