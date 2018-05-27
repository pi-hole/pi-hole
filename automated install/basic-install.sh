#!/usr/bin/env bash
# shellcheck disable=SC1090

#
# Pi-hole: A black hole for Internet advertisements
# (c) 2017-2018 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Installs and Updates Pi-hole
#  Install with this command (from your Linux machine):
#
#  curl -sSL https://install.pi-hole.net | bash
#
# License
#  This file is copyright under the latest version of the EUPL.
#  Please see LICENSE file for your rights under this license.
#
# Donations
#  Please consider donating to keep this project running.
#  pi-hole.net/donate
#

# -e option instructs bash to immediately exit if any command [1] has a non-zero exit status.
# We do not want users to end up with a partially working install, so we exit the script
# instead of continuing the installation with something broken.
set -e


#-------- Important Variables

# location for the installation log
INSTALL_LOG_LOC=/etc/pihole/install.log

# Contains various installation parameters which will be used when updating Pi-hole.
SETUP_VARS=/etc/pihole/setupVars.conf

# The Pi-hole dashboard uses lighttpd as its web server and this is its config file.
LIGHTTPD_CONFIG=/etc/lighttpd/lighttpd.conf

# Contains variable definitions for colorized output.
COLTABLE=/opt/pihole/COL_TABLE

# Git repository of the web interface and its installation directory.
WEB_INTERFACE_GIT_URL="https://github.com/pi-hole/AdminLTE.git"
WEB_INTERFACE_DIR="/var/www/html/admin"

# Git repository of Pi-hole and the location for its local clone.
PIHOLE_GIT_URL="https://github.com/pi-hole/pi-hole.git"
PI_HOLE_LOCAL_REPO="/etc/.pihole"

# List of all Pi-hole files, which is used for removing old versions during installations and updates.
PI_HOLE_FILES=(chronometer list piholeDebug piholeLogFlush setupLCD update version gravity uninstall webpage)

# This folder is where the Pi-hole scripts will be installed.
PI_HOLE_INSTALL_DIR="/opt/pihole"

# Used to keep track of whether the script is used for a repair/update or reconfiguration.
USE_UPDATE_VARS=false

# the file containing the adlists
ADLIST_FILE="/etc/pihole/adlists.list"

# IP addresses of the host running Pi-hole. Will be set throughout the setup.
IPV4_ADDRESS=""
IPV6_ADDRESS=""

# By default, query logging is enabled and the dashboard is set to be installed
QUERY_LOGGING=true
INSTALL_WEB=true


#------- Undocumented Flags
# These are undocumented flags; some of which we can use when repairing an installation
SKIP_SPACE_CHECK=false
RECONFIGURE=false
RUN_UNATTENDED=false
INSTALL_WEB_SERVER=true
# Check arguments for the undocumented flags
for var in "$@"; do
  case "$var" in
  "--reconfigure" ) RECONFIGURE=true;;
  "--i_do_not_follow_recommendations" ) SKIP_SPACE_CHECK=true;;
  "--unattended" ) RUN_UNATTENDED=true;;
  "--disable-install-webserver" ) INSTALL_WEB_SERVER=false;;
  esac
done



#-------- Screen Size
# Determine the screen size for displaying whiptail dialogs or default to 80x24 if it can not be detected.
screen_size=$(stty size 2>/dev/null || echo 24 80)
rows=$(echo "${screen_size}" | awk '{print $1}')
columns=$(echo "${screen_size}" | awk '{print $2}')

# Divide by two so the dialogs take up half of the screen, which looks nice.
R=$(( rows / 2 ))
C=$(( columns / 2 ))

# Unless the screen is tiny
R=$(( R < 20 ? 20 : R ))
C=$(( C < 70 ? 70 : C ))


#------- Colorized Output
# For the output to be colorized, we will either use the colors as defined in the file ${COLTABLE} or fall
# back to a default configuration if the file does not exist.

if [[ -f "${COLTABLE}" ]]; then
  source "${COLTABLE}"

else
  COL_NC='\e[0m' # No Color
  COL_LIGHT_GREEN='\e[1;32m'
  COL_LIGHT_RED='\e[1;31m'
  TICK="[${COL_LIGHT_GREEN}✓${COL_NC}]"
  CROSS="[${COL_LIGHT_RED}✗${COL_NC}]"
  INFO="[i]"
  DONE="${COL_LIGHT_GREEN} done!${COL_NC}"
  OVER="\\r\\033[K"
fi


#------- Functions

# Prints the Pi-hole logo, to let users know that this is a Pi-hole, LLC product.
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

# Compatibility
distro_check() {

  # the package manager itself
  PKG_MANAGER=""
  # the command used for updating the package cache
  UPDATE_PKG_CACHE=""
  # the command used for installing new packages
  PKG_INSTALL=""
  # ?
  PKG_COUNT=""

  # dependencies for the installer, Pi-hole and the web dashboard
  INSTALLER_DEPS=""
  PIHOLE_DEPS=""
  PIHOLE_WEB_DEPS=""

  # the user, group and config file for the web server
  LIGHTTPD_USER=""
  LIGHTTPD_GROUP=""
  LIGHTTPD_CFG=""


  # Debian-family (Debian, Raspbian, Ubuntu)
  # If apt-get is installed, then we know it's part of the Debian family.
  if command -v apt-get &> /dev/null; then

    PKG_MANAGER="apt-get"
    UPDATE_PKG_CACHE="${PKG_MANAGER} update"
    PKG_INSTALL=("${PKG_MANAGER}" --yes --no-install-recommends install)

    # grep -c will return 1 retVal on 0 matches, block this throwing the set -e with an OR TRUE
    PKG_COUNT="${PKG_MANAGER} -s -o Debug::NoLocking=true upgrade | grep -c ^Inst || true"

    # Debian 7 doesn't have iproute2. Use it if the dryrun install is successful, otherwise use iproute.
    local iproutePkg
    if "${PKG_MANAGER}" install --dry-run iproute2 > /dev/null 2>&1; then
      iproutePkg="iproute2"
    else
      iproutePkg="iproute"
    fi

    # We prefer the php metapackage if it's there, otherwise use the php5 packages.
    if "${PKG_MANAGER}" install --dry-run php > /dev/null 2>&1; then
      phpVer="php"
    else
      phpVer="php5"
    fi

    # Determine the available version of `php-sqlite`.
    if "${PKG_MANAGER}" install --dry-run "${phpVer}"-sqlite3 > /dev/null 2>&1; then
      phpSqlite="sqlite3"
    else
      phpSqlite="sqlite"
    fi

    INSTALLER_DEPS=(apt-utils dialog debconf dhcpcd5 git "${iproutePkg}" whiptail)
    PIHOLE_DEPS=(bc cron curl dnsutils iputils-ping lsof netcat psmisc sudo unzip wget idn2 sqlite3 libcap2-bin dns-root-data resolvconf)
    PIHOLE_WEB_DEPS=(lighttpd "${phpVer}"-common "${phpVer}"-cgi "${phpVer}"-"${phpSqlite}")

    LIGHTTPD_USER="www-data"
    LIGHTTPD_GROUP="www-data"
    LIGHTTPD_CFG="lighttpd.conf.debian"

    # Waits until the dpkg lock is free and packages can be installed/configured.
    test_dpkg_lock() {
        # Keep track of iterations. TODO: Why?
        local i=0
        # fuser shows which processes use the named files, sockets, or filesystems.
        # So while the dpkg lock is true, keep waiting.
        while fuser /var/lib/dpkg/lock >/dev/null 2>&1 ; do
          sleep 0.5
          ((i=i+1))
        done

        # Always return success, since we only return if there is no lock (anymore).
        return 0
      }

  # Fedora (Fedora, Redhat, CentOS)
  # If rpm is installed, then we know it's part of the Fedora family.
  elif command -v rpm &> /dev/null; then

    # Determine if dnf or yum is the package manager.
    if command -v dnf &> /dev/null; then
      PKG_MANAGER="dnf"
    else
      PKG_MANAGER="yum"
    fi

    # Fedora and family update cache on every PKG_INSTALL call, no need for a separate update.
    UPDATE_PKG_CACHE=":"
    PKG_INSTALL=("${PKG_MANAGER}" install -y)
    PKG_COUNT="${PKG_MANAGER} check-update | egrep '(.i686|.x86|.noarch|.arm|.src)' | wc -l"

    INSTALLER_DEPS=(dialog git iproute net-tools newt procps-ng)
    PIHOLE_DEPS=(bc bind-utils cronie curl findutils nmap-ncat sudo unzip wget libidn2 psmisc)
    PIHOLE_WEB_DEPS=(lighttpd lighttpd-fastcgi php php-common php-cli php-pdo)

    # EPEL (https://fedoraproject.org/wiki/EPEL) is required for lighttpd on CentOS
    if grep -qi 'centos' /etc/redhat-release; then
      INSTALLER_DEPS=("${INSTALLER_DEPS[@]}" "epel-release");
    fi

    LIGHTTPD_USER="lighttpd"
    LIGHTTPD_GROUP="lighttpd"
    LIGHTTPD_CFG="lighttpd.conf.fedora"

  # If neither apt-get or rmp/dnf are found, it is not a supported OS. Exit the installer.
  else
    echo -e "  ${CROSS} OS distribution not supported"
    exit 1
  fi
}

# Checks if a given directory is a git repository.
#  $1: the directory to be checked
is_repo() {
  local directory="${1}"

  # Remember the current directory, to return to it at the end.
  local curdir="${PWD}"

  # a variable to store the return code
  local rc

  # If the given directory exists, use git to check if it is a repository.
  if [[ -d "${directory}" ]]; then

    cd "${directory}"

    # git -C is not used here to support git versions older than 1.8.4
    git status --short &> /dev/null || rc=$?

  # Otherwise, it cannot be a git repository. Return a non-zero code.
  else
    rc=1
  fi

  # Move back into the directory the user started in
  cd "${curdir}"

  # Return the code; if one is not set, return 0
  return "${rc:-0}"
}

# Clones a remote git repository to a local directory.
#  $1: the local directory
#  $2: the remote git repository's URL
make_repo() {
  local directory="${1}"
  local remoteRepo="${2}"

  # Create a message to tell the user what is currently happening and display it.
  local msg="Clone ${remoteRepo} into ${directory}"
  echo -ne "  ${INFO} ${msg}..."

  # If the directory exists, delete everything in it so git can clone into it.
  if [[ -d "${directory}" ]]; then
    rm -rf "${directory}"
  fi

  # Clone the repo. If this command fails, return its exit code.
  git clone -q --depth 1 "${remoteRepo}" "${directory}" &> /dev/null || return $?

  # Show a completion message and return success.
  echo -e "${OVER}  ${TICK} ${msg}"
  return 0
}

# Updates a local git repository by cloning the most recent version from its origin.
#  $1: the directory containing the local git repository
update_repo() {
  local directory="${1}"

  # Remember the current directory, to return to it at the end.
  local curdir="${PWD}"

  # Create a message to tell the user what is currently happening and display it.
  local msg="Update repo in ${1}"
  echo -ne "  ${INFO} ${msg}..."

  # Move into the given directory or exit with an error if we cannot.
  cd "${directory}" &> /dev/null || return 1

  # Stash any local commits as they conflict with our working code.
  git stash --all --quiet &> /dev/null || true # Okay for stash failure
  git clean --quiet --force -d || true # Okay for already clean directory

  # Pull the latest commits.
  git pull --quiet &> /dev/null || return $?

  # Move back into the original directory or exit with an error if we cannot.
  cd "${curdir}" &> /dev/null || return 1

  # Show a completion message and return succcess.
  echo -e "${OVER}  ${TICK} ${msg}"
  return 0
}

# Either clones a remote git repository to a local directory or updates the local git repository
# if it already exists.
#  $1: the local directory (possibly containing a git repository)
#  $2: the remote git repository's URL
get_git_files() {
  local directory="${1}"
  local remoteRepo="${2}"

  # Create a message to tell the user what is currently happening and display it.
  local msg="Check for existing repository in ${1}"
  echo -ne "  ${INFO} ${msg}..."

  # If the given directory is a repository, update its contents.
  if is_repo "${directory}"; then
    echo -e "${OVER}  ${TICK} ${msg}"

    # Update the repo. If this command fails, show an error and exit.
    update_repo "${directory}" || { echo -e "\\n  ${COL_LIGHT_RED}Error: Could not update local repository. Contact support.${COL_NC}"; exit 1; }

  # If it's not a repository, try cloning the given remote repository in its place.
  else
    echo -e "${OVER}  ${CROSS} ${msg}"

    # Attempt to clone the repository. If the command fails, show an error and exit.
    make_repo "${directory}" "${remoteRepo}" || { echo -e "\\n  ${COL_LIGHT_RED}Error: Could not update local repository. Contact support.${COL_NC}"; exit 1; }
  fi

  # As all failing paths exited already, return success.
  echo ""
  return 0
}

# Resets a local git repository to get rid of any local changes.
#  $1: the directory containing the local git repository
reset_repo() {
  local directory="${1}"

  # Create a message to tell the user what is currently happening and display it.
  local msg="Resetting repository within ${1}..."
  echo -ne "  ${INFO} ${msg}"

  # Move into the given directory or exit with an error if we cannot.
  cd "${directory}" &> /dev/null || return 1

  # Use git to remove the local changes. If the command fails, return its exit code.
  git reset --hard &> /dev/null || return $?

  # Show a completion message and return success.
  echo -e "${OVER}  ${TICK} ${msg}"
  return 0
}

# Determines the Pi-hole server's IPv4 address and default gateway. These are needed for the DNS
# server to answer queries and redirect unwanted requests.
find_IPv4_information() {
  # Find IP used to route to outside world by checking the route to Google's public DNS server.
  local route=$(ip route get 8.8.8.8)
  # Get just the IP address.
  local ipv4bare=$(awk '{print $7}' <<< "${route}")
  # Append the CIDR notation to the IP address.
  IPV4_ADDRESS=$(ip -o -f inet addr show | grep "${IPv4bare}" |  awk '{print $4}' | awk 'END {print}')
  # Get the default gateway (the way to reach the Internet).
  IPV4_GATEWAY=$(awk '{print $3}' <<< "${route}")
}

# Determines all active network interfaces.
get_available_interfaces() {
  # There may be more than one so they're all stored in a variable.
  AVAILABLE_INTERFACES=$(ip --oneline link show up | grep -v "lo" | awk '{print $2}' | cut -d':' -f1 | cut -d'@' -f1)
}

# Displays the dialogs the user sees when first running the installer.
welcome_dialogs() {
  # Display the welcome dialog using an approriately sized window via the calculation conducted earlier in the script.
  whiptail --msgbox --backtitle "Welcome" --title "Pi-hole automated installer" "\\n\\nThis installer will transform your device into a network-wide ad blocker!" "${R}" "${C}"

  # Request that users donate if they enjoy the software since we all work on it in our free time.
  whiptail --msgbox --backtitle "Plea" --title "Free and open source" "\\n\\nThe Pi-hole is free, but powered by your donations:  http://pi-hole.net/donate" "${R}" "${C}"

  # Explain the need for a static address.
  whiptail --msgbox --backtitle "Initiating network interface" --title "Static IP Needed" "\\n\\nThe Pi-hole is a SERVER so it needs a STATIC IP ADDRESS to function properly.

In the next section, you can choose to use your current network settings (DHCP) or to manually edit them." "${R}" "${C}"
}

# Verifies if there is enough free disk space before installing.
# 50MB is the minimum space needed (45MB install (includes web admin bootstrap/jquery libraries etc) + 5MB one day of logs.)
verify_free_disk_space() {

  # a message for telling the user what is happening
  local msg="Disk space check"
  # Required space in KB.
  local required_free_kilobytes=51200

  # Calculate the existing free space on this machine.
  local existing_free_kilobytes=$(df -Pk | grep -m1 '\/$' | awk '{print $4}')

  # If the existing space is not an integer, show an error that we can't determine the free space and exit.
  if ! [[ "${existing_free_kilobytes}" =~ ^([0-9])+$ ]]; then
    echo -e "  ${CROSS} ${msg}
      Unknown free disk space!
      We were unable to determine available free disk space on this system.
      You may override this check, however, it is not recommended
      The option '${COL_LIGHT_RED}--i_do_not_follow_recommendations${COL_NC}' can override this
      e.g: curl -L https://install.pi-hole.net | bash /dev/stdin ${COL_LIGHT_RED}<option>${COL_NC}"
    exit 1

  # If there is insufficient free disk space, show an error message and exit.
  elif [[ "${existing_free_kilobytes}" -lt "${required_free_kilobytes}" ]]; then
    echo -e "  ${CROSS} ${msg}
      Your system disk appears to only have ${existing_free_kilobytes} KB free
      It is recommended to have a minimum of ${required_free_kilobytes} KB to run the Pi-hole"

    # If the vcgencmd command exists, it's probably a Raspbian install, so show a message about expanding the filesystem.
    if command -v vcgencmd &> /dev/null; then
      echo "      If this is a new install you may need to expand your disk
      Run 'sudo raspi-config', and choose the 'expand file system' option
      After rebooting, run this installation again
      e.g: curl -L https://install.pi-hole.net | bash"
    fi

    # Show there is not enough free space and exit with an error.
    echo -e "\\n      ${COL_LIGHT_RED}Insufficient free space, exiting...${COL_NC}"
    exit 1

  # Otherwise, show a completion message.
  else
    echo -e "  ${TICK} ${msg}"
  fi
}

# Displays a cancelation message and exits the installer.
cancel() {
    echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}";
    exit 1;
}

# Displays a dialog that let's the user pick an interface to use with Pi-hole.
choose_interface() {

  # Find out how many interfaces are available to choose from.
  local interfaceCount=$(echo "${AVAILABLE_INTERFACES}" | wc -l)

  # If there is one interface, set it as the interface to use.
  if [[ "${interfaceCount}" -eq 1 ]]; then
      PIHOLE_INTERFACE="${AVAILABLE_INTERFACES}"

  # Otherwise, display a dialog to the user to let him chose which interface to use.
  else
      # an array to contain the options
      local interfacesArray=()

      # Iterate through the list of interfaces and add them to the list of choices for the user.
      local firstLoop=1
      while read -r line; do
        # Use a variable to set this option as OFF to begin with.
        local mode="OFF"

        # If it's the first loop, set this interface as the one to use (ON).
        if [[ "${firstLoop}" -eq 1 ]]; then
          mode="ON"
          firstLoop=0
        fi

        # Add the interface and its mode to the array of options.
        interfacesArray+=("${line}" "available" "${mode}")

      # Feed the available interfaces into this while loop.
      done <<< "${AVAILABLE_INTERFACES}"

      # The whiptail command that will be run, stored in a variable.
      local chooseInterfaceCmd=(whiptail --separate-output --radiolist "Choose An Interface (press space to select)" "${R}" "${C}" "${interfaceCount}")
      # Now run the command using the interfaces saved into the array.
      local chooseInterfaceOptions=$("${chooseInterfaceCmd[@]}" "${interfacesArray[@]}" 2>&1 >/dev/tty) || cancel

      # Loop through the user's choices and set them as the interface to use. TODO: Why a loop? Shouldn't this be only one value?
      for desiredInterface in ${chooseInterfaceOptions}; do
        PIHOLE_INTERFACE="${desiredInterface}"
        # Show this information to the user.
        echo -e "  ${INFO} Using interface: $PIHOLE_INTERFACE"
      done
  fi
}

# Determines if a given IPv6 address is a unique local address (ULA), global unicast address (GLA)
# or a link-local (LL) address.
# This caused problems for some users when their ISP changed their IPv6 addresses.
# See https://github.com/pi-hole/pi-hole/issues/1473#issuecomment-301745953
#  $1: the IPv6 address to be checked
test_ipv6() {
  # first will contain fda2 (ULA)
  local first="$(cut -f1 -d":" <<< "$1")"
  # value1 will contain 253 which is the decimal value corresponding to 0xfd
  local value1=$(( (0x$first)/256 ))
  # value 2 will contain 162 which is the decimal value corresponding to 0xa2
  local value2=$(( (0x$first)%256 ))

  # the ULA test is testing for fc00::/7 according to RFC 4193
  if (( (value1&254)==252 )); then
    echo "ULA"
  fi

  # the GUA test is testing for 2000::/3 according to RFC 4291
  if (( (value1&112)==32 )); then
    echo "GUA"
  fi

  # the LL test is testing for fe80::/10 according to RFC 4193
  if (( (value1)==254 )) && (( (value2&192)==128 )); then
    echo "Link-local"
  fi
}

# Determines if the Pi-hole server has a suitable IPv6 address to be used for blocking
# ads and displays the information to the user.
use_ipv6_dialog() {
  # Get a list of all available IPv6 addresses.
  ipv6Addresses=($(ip -6 address | grep 'scope global' | awk '{print $2}'))

  # For each address in the array above, determine the type of IPv6 address it is.
  for i in "${ipv6Addresses[@]}"; do
    local type=$(test_ipv6 "$i")

    # If it's a ULA address, use it and store it as a global variable.
    [[ "${type}" == "ULA" ]] && ULA_ADDRESS="${i%/*}"

    # GUA addresses are not preferred, but we can still use it, so store it as a global variable too.
    [[ "${type}" == "GUA" ]] && GUA_ADDRESS="${i%/*}"
  done

  # Determine which address to be used: Prefer ULA over GUA or don't use any if none were found.
  # If the ULA_ADDRESS contains a value, use it.
  if [[ ! -z "${ULA_ADDRESS}" ]]; then
    IPV6_ADDRESS="${ULA_ADDRESS}"
    echo -e "  ${INFO} Found IPv6 ULA address, using it for blocking IPv6 ads"

  # Otherwise, if the GUA_ADDRESS has a value, use it instead.
  elif [[ ! -z "${GUA_ADDRESS}" ]]; then
    echo -e "  ${INFO} Found IPv6 GUA address, using it for blocking IPv6 ads"
    IPV6_ADDRESS="${GUA_ADDRESS}"

  # If no suitable address was found, disable IPv6 blocking.
  else
    echo -e "  ${INFO} Unable to find IPv6 ULA/GUA address, IPv6 adblocking will not be enabled"
    IPV6_ADDRESS=""
  fi

  # If an IPV6_ADDRESS was found, display that IPv6 is supported and will be used.
  if [[ ! -z "${IPV6_ADDRESS}" ]]; then
    whiptail --msgbox --backtitle "IPv6..." --title "IPv6 Supported" "$IPV6_ADDRESS will be used to block ads." "${R}" "${C}"
  fi
}

# Displays a dialog letting the user chose whether to use IPv4, IPv6 or both for blocking ads.
use_ipv4_andor_ipv6() {

  # Prepare the whiptail dialog.
  local cmd=(whiptail --separate-output --checklist "Select Protocols (press space to select)" "${R}" "${C}" 2)

  # Prepare the dialog's options.
  local options=(IPv4 "Block ads over IPv4" on # IPv4 (on by default)
    IPv6 "Block ads over IPv6" on) # IPv6 (on by default if available)

  # Display the dialog to the user and store his choices in a variable.
  local choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty) || cancel

  # Loop through the choices and set which addresses are to be used.
  local useIPv4
  local useIPv6
  for choice in ${choices}; do
    case "${choice}" in
      IPv4  )   useIPv4=true;;
      IPv6  )   useIPv6=true;;
    esac
  done

  # If IPv4 is to be used, get the required information.
  if [[ "${useIPv4}" ]]; then
    find_IPv4_information
    get_static_ipv4_settings
    set_static_ipv4
  fi

  # If IPv6 is to be used, get the required information.
  if [[ "${useIPv6}" ]]; then
    use_ipv6_dialog
  fi

  # Show the information to the user.
  echo -e "  ${INFO} IPv4 address: ${IPV4_ADDRESS}"
  echo -e "  ${INFO} IPv6 address: ${IPV6_ADDRESS}"

  # If neither protocol is selected, show an error and exit.
  if [[ ! "${useIPv4}" ]] && [[ ! "${useIPv6}" ]]; then
    echo -e "  ${COL_LIGHT_RED}Error: Neither IPv4 or IPv6 selected${COL_NC}"
    exit 1
  fi
}

# Displays a dialog letting the user chose between using the automatically detected IPv4 address as a static
# address or setting a different configuration.
get_static_ipv4_settings() {

  # Ask if the user wants to use the automatically detected DHCP settings as their static IP.
  # This is useful for users that are using DHCP reservations; then we can just use the information gathered via our functions.
  if whiptail --backtitle "Calibrating network interface" --title "Static IP Address" --yesno "Do you want to use your current network settings as a static address?
          IP address:    ${IPV4_ADDRESS}
          Gateway:       ${IPV4_GATEWAY}" "${R}" "${C}"; then
    # If they choose yes, let the user know that the IP address will not be available via DHCP and may cause a conflict.
    whiptail --msgbox --backtitle "IP information" --title "FYI: IP Conflict" "It is possible your router could still try to assign this IP to a device, which would cause a conflict.  But in most cases the router is smart enough to not do that.
If you are worried, either manually set the address, or modify the DHCP reservation pool so it does not include the IP you want.
It is also possible to use a DHCP reservation, but if you are going to do that, you might as well set a static address." "${R}" "${C}"

  # Otherwise, we need to ask the user to input their desired settings.
  else
    # Start by getting the IPv4 address (pre-filling it with info gathered from DHCP).
    # Start a loop to let the user enter their information with the chance to go back and edit it if necessary.
    local ipSettingsCorrect=False
    until [[ "${ipSettingsCorrect}" = True ]]; do

      # Ask for the IPv4 address
      IPV4_ADDRESS=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 address" --inputbox "Enter your desired IPv4 address" "${R}" "${C}" "${IPV4_ADDRESS}" 3>&1 1>&2 2>&3) || cancel
      echo -e "  ${INFO} Your static IPv4 address: ${IPV4_ADDRESS}"

      # Ask for the gateway.
      IPV4_GATEWAY=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 gateway (router)" --inputbox "Enter your desired IPv4 default gateway" "${R}" "${C}" "${IPV4_GATEWAY}" 3>&1 1>&2 2>&3) || cancel
      echo -e "  ${INFO} Your static IPv4 gateway: ${IPV4_GATEWAY}"

      # Give the user a chance to review their settings before moving on.
      if whiptail --backtitle "Calibrating network interface" --title "Static IP Address" --yesno "Are these settings correct?
        IP address: ${IPV4_ADDRESS}
        Gateway:    ${IPV4_GATEWAY}" "${R}" "${C}"; then
        # After that's done, the loop ends and we move on
        ipSettingsCorrect=True

      # If the settings are wrong, the loop continues
      else
        ipSettingsCorrect=False
      fi
    done
  fi
}

# Configures DHCPCD, setting the network interface, static IPv4 address and static IPv4 gateway to be used.
# Also instructs DHCPCD to use the Pi-hole server itself as its DNS server.
set_dhcpcd() {
  echo "interface ${PIHOLE_INTERFACE}
  static ip_address=${IPV4_ADDRESS}
  static routers=${IPV4_GATEWAY}
  static domain_name_servers=127.0.0.1" | tee -a /etc/dhcpcd.conf >/dev/null
}

# Configures the DHCP client for both Debian and Fedora family OSs using either DHCPCD for Debian or
# the ifcfg-files for Fedora. Sets the DHCP client's network interface, static IPv4 address, static IPv4
# gateway and DNS servers.
set_static_ipv4() {

  # Debian-family OS
  if [[ -f "/etc/dhcpcd.conf" ]]; then
    # If the IPv4 address is already in the file, nothing needs to be done.
    if grep -q "${IPV4_ADDRESS}" /etc/dhcpcd.conf; then
      echo -e "  ${INFO} Static IP already configured"

    # Otheriwse, set the IPv4 address to be used.
    else
      # Set it using our function.
      set_dhcpcd

      # Then use the ip command to immediately set the new address.
      ip addr replace dev "${PIHOLE_INTERFACE}" "${IPV4_ADDRESS}"

      # Also give a warning that the user may need to reboot their system.
      echo -e "  ${TICK} Set IP address to ${IPV4_ADDRESS%/*}
      You may need to restart after the install is complete"
    fi

  # Fedora-family OS
  elif [[ -f "/etc/sysconfig/network-scripts/ifcfg-${PIHOLE_INTERFACE}" ]];then

    local ifcfgFile=/etc/sysconfig/network-scripts/ifcfg-"${PIHOLE_INTERFACE}"
    local ipAddr=$(echo "${IPV4_ADDRESS}" | cut -f1 -d/)

    # Check if the desired IP is already set.
    if grep -Eq "${ipAddr}(\\b|\\/)" "${ifcfgFile}"; then
      echo -e "  ${INFO} Static IP already configured"

    # Otherwise, put the IPv4 address into the ifcfg file.
    else
      # Put the IP in variables without the CIDR notation
      local cidr=$(echo "${IPV4_ADDRESS}" | cut -f2 -d/)

      # Backup the existing interface configuration:
      cp "${ifcfgFile}" "${ifcfgFile}".pihole.orig

      # Build the new configuration file using the GLOBAL variables we have
      {
        echo "# Configured via Pi-hole installer"
        echo "DEVICE=$PIHOLE_INTERFACE"
        echo "BOOTPROTO=none"
        echo "ONBOOT=yes"
        echo "IPADDR=$ipAddr"
        echo "PREFIX=$cidr"
        echo "GATEWAY=$IPV4_GATEWAY"
        echo "DNS1=$PIHOLE_DNS_1"
        echo "DNS2=$PIHOLE_DNS_2"
        echo "USERCTL=no"
      }> "${ifcfgFile}"

      # Use ip to immediately set the new address.
      ip addr replace dev "${PIHOLE_INTERFACE}" "${IPV4_ADDRESS}"

      # If NetworkMangler command exists and is ready to mangle, tell it to read our new sysconfig file.
      if command -v nmcli &> /dev/null && nmcli general status &> /dev/null; then
        nmcli con load "${ifcfgFile}" > /dev/null
      fi

      # Show a warning that the user may need to restart.
      echo -e "  ${TICK} Set IP address to ${IPV4_ADDRESS%/*}
      You may need to restart after the install is complete"
    fi

  # unsupported OS
  else
    echo -e "  ${INFO} Warning: Unable to locate configuration file to set static IPv4 address"
    exit 1
  fi
}

# Verifies that the given value is a syntactically correct IPv4 address.
#  $1: the value to be checked
valid_ip() {
  local ip="${1}"

  # a variable to store the return code
  local rc

  # If the IP matches the format xxx.xxx.xxx.xxx,
  if [[ "${ip}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    # Save the old Internal Field Separator in a variable
    OIFS="${IFS}"
    # and set the new one to a dot (period)
    IFS='.'
    # Put the IP into an array
    ip=(${ip})
    # Restore the IFS to what it was
    IFS="${OIFS}"
    ## Evaluate each octet by checking if it's less than or equal to 255 (the max for each octet)
    [[ "${ip[0]}" -le 255 && "${ip[1]}" -le 255 \
    && "${ip[2]}" -le 255 && "${ip[3]}" -le 255 ]]

    # Save the exit code
    rc=$?
  fi

  # Return the code; if one is not set, return 1
  return "${rc:-1}"
}

# Displays a dialog to let the user chose which upstream DNS server to use or to provide their own.
set_dns() {

  # In an array, list the available upstream providers.
  local DNSChooseOptions=(Google ""
      OpenDNS ""
      Level3 ""
      Norton ""
      Comodo ""
      DNSWatch ""
      Quad9 ""
      FamilyShield ""
      Cloudflare ""
      Custom "")

  # In a whiptail dialog, let the user chose from these options.
  local DNSchoices=$(whiptail --separate-output --menu "Select Upstream DNS Provider. To use your own, select Custom." "${R}" "${C}" 7 \
    "${DNSChooseOptions[@]}" 2>&1 >/dev/tty) || cancel

  # Display the selection and set the global variables PIHOLE_DNS_1 and PIHOLE_DNS_2 according to the user's choice.
  echo -ne "  ${INFO} Using "
  case "${DNSchoices}" in
    Google)
      echo "Google DNS servers"
      PIHOLE_DNS_1="8.8.8.8"
      PIHOLE_DNS_2="8.8.4.4"
      ;;
    OpenDNS)
      echo "OpenDNS servers"
      PIHOLE_DNS_1="208.67.222.222"
      PIHOLE_DNS_2="208.67.220.220"
      ;;
    Level3)
      echo "Level3 servers"
      PIHOLE_DNS_1="4.2.2.1"
      PIHOLE_DNS_2="4.2.2.2"
      ;;
    Norton)
      echo "Norton ConnectSafe servers"
      PIHOLE_DNS_1="199.85.126.10"
      PIHOLE_DNS_2="199.85.127.10"
      ;;
    Comodo)
      echo "Comodo Secure servers"
      PIHOLE_DNS_1="8.26.56.26"
      PIHOLE_DNS_2="8.20.247.20"
      ;;
    DNSWatch)
      echo "DNS.WATCH servers"
      PIHOLE_DNS_1="84.200.69.80"
      PIHOLE_DNS_2="84.200.70.40"
      ;;
    Quad9)
      echo "Quad9 servers"
      PIHOLE_DNS_1="9.9.9.9"
      PIHOLE_DNS_2="149.112.112.112"
      ;;
    FamilyShield)
      echo "FamilyShield servers"
      PIHOLE_DNS_1="208.67.222.123"
      PIHOLE_DNS_2="208.67.220.123"
      ;;
    Cloudflare)
      echo "Cloudflare servers"
      PIHOLE_DNS_1="1.1.1.1"
      PIHOLE_DNS_2="1.0.0.1"
      ;;
    Custom)
      # Let the user enter custom IP addresses.
      # Start a loop to allow for corrections.
      local DNSSettingsCorrect=False
      local strInvalid="Invalid"
      until [[ "${DNSSettingsCorrect}" = True ]]; do

        # Prepopulate the dialog, if the user entered valid addresses in a previous iteration.
        if [[ ! "${PIHOLE_DNS_1}" ]]; then
          if [[ ! "${PIHOLE_DNS_2}" ]]; then
            prePopulate=""
          else
            prePopulate=", ${PIHOLE_DNS_2}"
          fi
        elif  [[ "${PIHOLE_DNS_1}" ]] && [[ ! "${PIHOLE_DNS_2}" ]]; then
          prePopulate="${PIHOLE_DNS_1}"
        elif [[ "${PIHOLE_DNS_1}" ]] && [[ "${PIHOLE_DNS_2}" ]]; then
          prePopulate="${PIHOLE_DNS_1}, ${PIHOLE_DNS_2}"
        fi

        # Show a dialog
        piholeDNS=$(whiptail --backtitle "Specify Upstream DNS Provider(s)"  --inputbox "Enter your desired upstream DNS provider(s), separated by a comma.\\n\\nFor example '8.8.8.8, 8.8.4.4'" "${R}" "${C}" "${prePopulate}" 3>&1 1>&2 2>&3) || cancel

        # Split the user's input in the primary and secondary IP address,
        PIHOLE_DNS_1=$(echo "${piholeDNS}" | sed 's/[, \t]\+/,/g' | awk -F, '{print$1}')
        PIHOLE_DNS_2=$(echo "${piholeDNS}" | sed 's/[, \t]\+/,/g' | awk -F, '{print$2}')

        # Check each address for validity. If it is valid, store it in a global variable so we can use it.
        if ! valid_ip "${PIHOLE_DNS_1}" || [[ ! "${PIHOLE_DNS_1}" ]]; then
          PIHOLE_DNS_1="${strInvalid}"
        fi
        if ! valid_ip "${PIHOLE_DNS_2}" && [[ "${PIHOLE_DNS_2}" ]]; then
          PIHOLE_DNS_2="${strInvalid}"
        fi

        # If either of the addresses are invalid, explain it to the user, clear it and start another iteration.
        if [[ "${PIHOLE_DNS_1}" == "${strInvalid}" ]] || [[ "${PIHOLE_DNS_2}" == "${strInvalid}" ]]; then
          whiptail --msgbox --backtitle "Invalid IP" --title "Invalid IP" "One or both entered IP addresses were invalid. Please try again.\\n\\n    DNS Server 1:   $PIHOLE_DNS_1\\n    DNS Server 2:   ${PIHOLE_DNS_2}" "${R}" "${C}"

          # Set the invalid variables back to nothing.
          if [[ "${PIHOLE_DNS_1}" == "${strInvalid}" ]]; then
            PIHOLE_DNS_1=""
          fi
          if [[ "${PIHOLE_DNS_2}" == "${strInvalid}" ]]; then
            PIHOLE_DNS_2=""
          fi

          # Since the settings will not work, stay in the loop.
          DNSSettingsCorrect=False

        # Otherwise, show the settings to the user.
        else
          # If the user confirms his choice, exit the loop.
          if (whiptail --backtitle "Specify Upstream DNS Provider(s)" --title "Upstream DNS Provider(s)" --yesno "Are these settings correct?\\n    DNS Server 1:   $PIHOLE_DNS_1\\n    DNS Server 2:   ${PIHOLE_DNS_2}" "${R}" "${C}"); then
            DNSSettingsCorrect=True
          # Otherwise, the loop continues.
          else
            DNSSettingsCorrect=False
          fi
        fi
      done
      ;;
  esac
}

# Allows the user to enable or disable query logging for the DNS server.
set_logging() {

  # Prepare the dialog to ask if the user wants to log queries.
  local logToggleCommand=(whiptail --separate-output --radiolist "Do you want to log queries?\\n (Disabling will render graphs on the Admin page useless):" "${R}" "${C}" 6)

  # Prepare the list of choices. Default is on.
  local logChooseOptions=("On (Recommended)" "" on
    Off "" off)

  # Display the dialog and get the user's choice.
  local logChoices=$("${logToggleCommand[@]}" "${logChooseOptions[@]}" 2>&1 >/dev/tty) || cancel

  # Set QUERY_LOGGING according to the user's choice.
  case "${logChoices}" in
    # If it's on, set the GLOBAL variable to true.
    "On (Recommended)")
      echo -e "  ${INFO} Logging On."
      QUERY_LOGGING=true
      ;;
    # Otherwise, set it to false.
    Off)
      echo -e "  ${INFO} Logging Off."
      QUERY_LOGGING=false
      ;;
  esac
}

# Displays a dialog asking the user whether to install the web dashboard.
set_admin_flag() {

  # Prepare the dialog to ask if the user wants to install the web dashboard.
  local webToggleCommand=(whiptail --separate-output --radiolist "Do you wish to install the web admin interface?" "${R}" "${C}" 6)

  # Prepare the list of choices. Default is on.
  local webChooseOptions=("On (Recommended)" "" on
    Off "" off)

  # Display the dialog and get the user's choice.
  local webChoices=$("${webToggleCommand[@]}" "${webChooseOptions[@]}" 2>&1 >/dev/tty) || cancel

  # Set INSTALL_WEB_INTERFACE according to the user's choice.
  case "${webChoices}" in
    # If it's on, set the GLOBAL variable to true.
    "On (Recommended)")
      echo -e "  ${INFO} Web Interface On"
      INSTALL_WEB_INTERFACE=true
      ;;
    # Otherwise, set it to false.
    Off)
      echo -e "  ${INFO} Web Interface Off"
      INSTALL_WEB_INTERFACE=false
      ;;
  esac

  # If the user has chosen to install the dashboard, ask if the users wants to install the LIGHTTPD server as well.
  # Skip this if the --disable-install-webserver argument was set.
  if [[ "${INSTALL_WEB_SERVER}" == true ]]; then

    # Prepare the new dialog and the options.
    webToggleCommand=(whiptail --separate-output --radiolist "Do you wish to install the web server (lighttpd)?\\n\\nNB: If you disable this, and, do not have an existing webserver installed, the web interface will not function." "${R}" "${C}" 6)
    webChooseOptions=("On (Recommended)" "" on
      Off "" off)

    # Display the dialog and get the user's choice.
    webChoices=$("${webToggleCommand[@]}" "${webChooseOptions[@]}" 2>&1 >/dev/tty) || cancel

  # Set INSTALL_WEB_SERVER according to the user's choice.
    case "${webChoices}" in
      "On (Recommended)")
        echo -e "  ${INFO} Web Server On"
        INSTALL_WEB_SERVER=true
        ;;
      Off)
        echo -e "  ${INFO} Web Server Off"
        INSTALL_WEB_SERVER=false
        ;;
    esac
  fi
}

# Displays a dialog to let the user choose from a list of blocklists to use.
choose_blocklists() {

  # Back up any existing adlist file, on the off chance that it exists. Useful in case of a reconfigure.
  if [[ -f "${ADLIST_FILE}" ]]; then
    mv "${ADLIST_FILE}" "${ADLIST_FILE}.old"
  fi

  # Prepare the dialog to ask which blocklists the user wants to use.
  local cmd=(whiptail --separate-output --checklist "Pi-hole relies on third party lists in order to block ads.\\n\\nYou can use the suggestions below, and/or add your own after installation\\n\\nTo deselect any list, use the arrow keys and spacebar" "${R}" "${C}" 7)

  # Prepare the list of choices. All on by default.
  local options=(StevenBlack "StevenBlack's Unified Hosts List" on
    MalwareDom "MalwareDomains" on
    Cameleon "Cameleon" on
    ZeusTracker "ZeusTracker" on
    DisconTrack "Disconnect.me Tracking" on
    DisconAd "Disconnect.me Ads" on
    HostsFile "Hosts-file.net Ads" on)

  # Display the dialog and get the user's choices.
  local choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty) || { rm "${ADLIST_FILE}" ; cancel; }

  # For each choice the user made, write the list's address to the ADLIST_FILE.
  for choice in ${choices}; do
    case "${choice}" in
      StevenBlack  )  echo "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" >> "${ADLIST_FILE}";;
      MalwareDom   )  echo "https://mirror1.malwaredomains.com/files/justdomains" >> "${ADLIST_FILE}";;
      Cameleon     )  echo "http://sysctl.org/cameleon/hosts" >> "${ADLIST_FILE}";;
      ZeusTracker  )  echo "https://zeustracker.abuse.ch/blocklist.php?download=domainblocklist" >> "${ADLIST_FILE}";;
      DisconTrack  )  echo "https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt" >> "${ADLIST_FILE}";;
      DisconAd     )  echo "https://s3.amazonaws.com/lists.disconnect.me/simple_ad.txt" >> "${ADLIST_FILE}";;
      HostsFile    )  echo "https://hosts-file.net/ad_servers.txt" >> "${ADLIST_FILE}";;
    esac
  done
}

# Sets up dnsmasq for Pi-hole.
version_check_dnsmasq() {

  local dnsmasqConf="/etc/dnsmasq.conf"
  local dnsmasqConfOrig="/etc/dnsmasq.conf.orig"
  local dnsmasqPiholeIdString="addn-hosts=/etc/pihole/gravity.list"
  local dnsmasqOriginalConfig="${PI_HOLE_LOCAL_REPO}/advanced/dnsmasq.conf.original"
  local dnsmasqPihole01Snippet="${PI_HOLE_LOCAL_REPO}/advanced/01-pihole.conf"
  local dnsmasqPihole01Location="/etc/dnsmasq.d/01-pihole.conf"

  # If the dnsmasq config file exists, either update it or leave it be.
  if [[ -f "${dnsmasqConf}" ]]; then
    echo -ne "  ${INFO} Existing dnsmasq.conf found..."

    # If gravity.list is found within this file, we presume it's from older versions on Pi-hole.
    # We will back it up and replace it with the most recent version.
    if grep -q "${dnsmasqPiholeIdString}" "${dnsmasqConf}"; then
      echo " it is from a previous Pi-hole install."
      echo -ne "  ${INFO} Backing up dnsmasq.conf to dnsmasq.conf.orig..."

      # Backup the original file.
      mv -f "${dnsmasqConf}" "${dnsmasqConfOrig}"
      echo -e "${OVER}  ${TICK} Backing up dnsmasq.conf to dnsmasq.conf.orig..."
      echo -ne "  ${INFO} Restoring default dnsmasq.conf..."

      # Replace it with the default.
      cp "${dnsmasqOriginalConfig}" "${dnsmasqConf}"
      echo -e "${OVER}  ${TICK} Restoring default dnsmasq.conf..."

    # Otherwise, we presume that it is supposed to be as it is.
    else
      echo " it is not a Pi-hole file, leaving alone!"
    fi

  # If a file cannot be found, restore the default one.
  else
    echo -ne "  ${INFO} No dnsmasq.conf found... restoring default dnsmasq.conf..."

    cp "${dnsmasqOriginalConfig}" "${dnsmasqConf}"
    echo -e "${OVER}  ${TICK} No dnsmasq.conf found... restoring default dnsmasq.conf..."
  fi

  # Now copy the pi-hole configuration for dnsmasq to the /etc/dnsmasq.d directory.
  echo -en "  ${INFO} Copying 01-pihole.conf to /etc/dnsmasq.d/01-pihole.conf..."

  # Check to see if dnsmasq directory exists (it may not due to being a fresh install and dnsmasq no longer being a dependency).
  if [[ ! -d "/etc/dnsmasq.d"  ]];then
    mkdir "/etc/dnsmasq.d"
  fi

  # Copy the new Pi-hole DNS config file into the dnsmasq.d directory.
  cp "${dnsmasqPihole01Snippet}" "${dnsmasqPihole01Location}"
  echo -e "${OVER}  ${TICK} Copying 01-pihole.conf to /etc/dnsmasq.d/01-pihole.conf"

  # Replace our placeholder values with the GLOBAL DNS variables that we populated earlier

  # First, swap in the interface to listen on
  sed -i "s/@INT@/$PIHOLE_INTERFACE/" "${dnsmasqPihole01Location}"

  # Then swap in the primary DNS server.
  if [[ "${PIHOLE_DNS_1}" != "" ]]; then
    sed -i "s/@DNS1@/$PIHOLE_DNS_1/" "${dnsmasqPihole01Location}"
  else
    sed -i '/^server=@DNS1@/d' "${dnsmasqPihole01Location}"
  fi

  # Next swap in the secondary DNS server.
  if [[ "${PIHOLE_DNS_2}" != "" ]]; then
    sed -i "s/@DNS2@/$PIHOLE_DNS_2/" "${dnsmasqPihole01Location}"
  else
    sed -i '/^server=@DNS2@/d' "${dnsmasqPihole01Location}"
  fi

  # Enable the use of the dnsmasq.d directory in dnsmasq.conf.
  sed -i 's/^#conf-dir=\/etc\/dnsmasq.d$/conf-dir=\/etc\/dnsmasq.d/' "${dnsmasqConf}"

  # If the user does not want to enable logging, disable it by commenting out the directive in 01-pihole.conf.
  if [[ "${QUERY_LOGGING}" == false ]] ; then
    sed -i 's/^log-queries/#log-queries/' "${dnsmasqPihole01Location}"
  # Otherwise, enable it by uncommenting said line.
  else
    # enable it by uncommenting the directive in the DNS config file
    sed -i 's/^#log-queries/log-queries/' "${dnsmasqPihole01Location}"
  fi
}

# Cleans an existing Pi-hole installation in a given directory to prepare for an upgrade or reinstallation.
#  $1: the directory containing the Pi-hole installation to be cleaned.
clean_existing() {
  local cleanDirectory="${1}"

  # Shift the argument list, dropping the first argument. The remaining parameters is a list of files to be removed.
  shift
  local oldFiles=( "$@" )

  # For each script found in the old files array
  for script in "${oldFiles[@]}"; do
    # Remove them
    rm -f "${cleanDirectory}/${script}.sh"
  done
}

# Installs the scripts from the local Pi-hole git repository at PI_HOLE_LOCAL_REPO to their various locations.
install_scripts() {

  # Create a message to tell the user what is currently happening and display it.
  local msg="Installing scripts from ${PI_HOLE_LOCAL_REPO}"
  echo -ne "  ${INFO} ${msg}..."

  # Clear out script files from Pi-hole scripts directory.
  clean_existing "${PI_HOLE_INSTALL_DIR}" "${PI_HOLE_FILES[@]}"

  # Install files from local core repository.
  if is_repo "${PI_HOLE_LOCAL_REPO}"; then

    # Move into the directory.
    cd "${PI_HOLE_LOCAL_REPO}"

    # Install the scripts by:
    #  -o setting the owner to the user
    #  -Dm755 create all leading components of destination except the last, then copy the source to the destination and setting the permissions to 755

    # This first one is the directory.
    install -o "${USER}" -Dm755 -d "${PI_HOLE_INSTALL_DIR}"

    # The rest are the scripts Pi-hole needs.
    install -o "${USER}" -Dm755 -t "${PI_HOLE_INSTALL_DIR}" gravity.sh
    install -o "${USER}" -Dm755 -t "${PI_HOLE_INSTALL_DIR}" ./advanced/Scripts/*.sh
    install -o "${USER}" -Dm755 -t "${PI_HOLE_INSTALL_DIR}" ./automated\ install/uninstall.sh
    install -o "${USER}" -Dm755 -t "${PI_HOLE_INSTALL_DIR}" ./advanced/Scripts/COL_TABLE
    install -o "${USER}" -Dm755 -t /usr/local/bin/ pihole
    install -Dm644 ./advanced/bash-completion/pihole /etc/bash_completion.d/pihole

    echo -e "${OVER}  ${TICK} ${msg}"

  # If the repository does not exist, something went wrong. Show an error and exit.
  else
    echo -e "${OVER}  ${CROSS} ${msg}
  ${COL_LIGHT_RED}Error: Local repo ${PI_HOLE_LOCAL_REPO} not found, exiting installer${COL_NC}"
    exit 1
  fi
}

# Installs the configs from the local Pi-hole git repository at PI_HOLE_LOCAL_REPO to their various locations.
install_configs() {

  # Display a message to tell the user what is currently happening.
  echo -e "  ${INFO} Installing configs from ${PI_HOLE_LOCAL_REPO}..."

  # Make sure Pi-hole's config files for dnsmasq are in place.
  version_check_dnsmasq

  # If the user chose to install the web server, install it.
  if [[ "${INSTALL_WEB_SERVER}" == true ]]; then

    # If the lighttpd configuration directory does not exist, create it.
    if [[ ! -d "/etc/lighttpd" ]]; then
      mkdir /etc/lighttpd

      # Set the owner to be the current user.
      chown "${USER}":root /etc/lighttpd

    # Otherwise, if the config file does exist, back it up.
    elif [[ -f "${LIGHTTPD_CONFIG}" ]]; then
      mv "${LIGHTTPD_CONFIG}" "${LIGHTTPD_CONFIG}".orig
    fi

    # Copy in the most recent version.
    cp "${PI_HOLE_LOCAL_REPO}"/advanced/"${LIGHTTPD_CFG}" "${LIGHTTPD_CONFIG}"

    # If there is a custom block page in the html/pihole directory, replace the 404 handler in lighttpd config.
    if [[ -f "/var/www/html/pihole/custom.php" ]]; then
      sed -i 's/^\(server\.error-handler-404\s*=\s*\).*$/\1"pihole\/custom\.php"/' "${LIGHTTPD_CONFIG}"
    fi

    # Make the configuration directories if they do not exist and set their owner to be the LIGHTTPD_USER.
    mkdir -p /var/run/lighttpd
    chown "${LIGHTTPD_USER}":"${LIGHTTPD_GROUP}" /var/run/lighttpd
    mkdir -p /var/cache/lighttpd/compress
    chown "${LIGHTTPD_USER}":"${LIGHTTPD_GROUP}" /var/cache/lighttpd/compress
    mkdir -p /var/cache/lighttpd/uploads
    chown "${LIGHTTPD_USER}":"${LIGHTTPD_GROUP}" /var/cache/lighttpd/uploads
  fi
}

# Stops a given service. May softfall as the service may not be installed.
#  $1: the service to be stopped
stop_service() {
  local service="${1}"

  # Create a message to tell the user what is currently happening and display it.
  local msg="Stopping ${service} service"
  echo -ne "  ${INFO} ${msg}..."

  # If systemctl exists, use it.
  if command -v systemctl &> /dev/null; then
    systemctl stop "${service}" &> /dev/null || true

  # Otherwise, fall back to using the service command.
  else
    service "${service}" stop &> /dev/null || true
  fi

  echo -e "${OVER}  ${TICK} ${msg}..."
}

# Starts a given service or restarts it, if it is already running.
#  $1: the service to be started
start_service() {
  local service="${1}"

  # Create a message to tell the user what is currently happening and display it.
  local msg="Starting ${service} service"
  echo -ne "  ${INFO} ${msg}..."

  # If systemctl exists, use it.
  if command -v systemctl &> /dev/null; then
    systemctl restart "${service}" &> /dev/null

  # Otherwise, fall back to using the service command.
  else
    service "${service}" restart &> /dev/null
  fi

  echo -e "${OVER}  ${TICK} ${msg}"
}

# Enables a given service, such that it will automatically be restarted after rebooting.
#  $1: the service to be enabled
enable_service() {
  local service="${1}"

  # Create a message to tell the user what is currently happening and display it.
  local msg="Enabling ${service} service to start on reboot"
  echo -ne "  ${INFO} ${msg}..."

  # If systemctl exists, use it.
  if command -v systemctl &> /dev/null; then
    systemctl enable "${service}" &> /dev/null

  # Otherwise, fall back to using update-rc.d.
  else
    update-rc.d "${service}" defaults &> /dev/null
  fi

  echo -e "${OVER}  ${TICK} ${msg}"
}

# Disables a given service so that it will not be restarted after rebooting.
#  $1: the service to be disabled
disable_service() {
  local service="${1}"

  # Create a message to tell the user what is currently happening and display it.
  local msg="Disabling ${service} service"
  echo -ne "  ${INFO} ${msg}..."

  # If systemctl exists, use it.
  if command -v systemctl &> /dev/null; then
    systemctl disable "${service}" &> /dev/null

  # Otherwise, fall back to using update-rc.d.
  else
    update-rc.d "${service}" disable &> /dev/null
  fi

  echo -e "${OVER}  ${TICK} ${msg}"
}

# Checks if a given service is enabled.
#  $1: the service to be checked
check_service_active() {
  local service="${1}"

  # If systemctl exists, use it.
  if command -v systemctl &> /dev/null; then
    systemctl is-enabled "${service}" > /dev/null

  # Otherwise, fall back to using the service command.
  else
    service "${service}" status > /dev/null
  fi
}

# Updates the package list on Debian family OS.
update_package_cache() {
  # Running apt-get update/upgrade with minimal output can cause some issues with
  # requiring user input (e.g password for phpmyadmin see #218)

  # Update package cache on apt based OSes. Do this every time since
  # it's quick and packages can be updated at any time.

  # Create a message to tell the user what is currently happening and display it.
  local msg="Update local cache of available packages"
  echo ""
  echo -ne "  ${INFO} ${msg}..."

  # If the updating command from distro_check succeeds, show a completion message.
  if eval "${UPDATE_PKG_CACHE}" &> /dev/null; then
    echo -e "${OVER}  ${TICK} ${str}"

  # Otherwise, show an error and exit.
  else
    echo -e "${OVER}  ${CROSS} ${str}"
    echo -ne "  ${COL_LIGHT_RED}Error: Unable to update package cache. Please try \"${UPDATE_PKG_CACHE}\"${COL_NC}"
    return 1
  fi
}

# Checks if all packages of the system are up to date and advises to update if updates are available.
notify_package_updates_available() {

  # Create a message to tell the user what is currently happening and display it.
  local msg="Checking ${PKG_MANAGER} for upgraded packages"
  echo -ne "\\n  ${INFO} ${msg}..."

  # Store the list of packages to be updated in a variable.
  local updatesToInstall=$(eval "${PKG_COUNT}")

  # Check if the kernel is up to date.
  if [[ -d "/lib/modules/$(uname -r)" ]]; then

    # If there are no updates to be installed, show it.
    if [[ "${updatesToInstall}" -eq 0 ]]; then
      echo -e "${OVER}  ${TICK} ${str}... up to date!"
      echo ""

    # Otherwise, advise the user to update after the installation has finished.
    else
      echo -e "${OVER}  ${TICK} ${str}... ${updatesToInstall} updates available"
      echo -e "  ${INFO} ${COL_LIGHT_GREEN}It is recommended to update your OS after installing the Pi-hole! ${COL_NC}"
      echo ""
    fi

  # Otherwise, display a warning that the installation may fail and instruct the user to reboot and try again.
  else
    echo -e "${OVER}  ${CROSS} ${str}
      Kernel update detected. If the install fails, please reboot and try again\\n"
  fi
}

# Keep track of how many times install_dependent_packages has run, to differentiate between installer and
# main dependency checks.
counter=0

# Installs all of Pi-holes dependencies.
#  $@: a platform dependent list of all packages Pi-hole depends on
install_dependent_packages() {
  declare -a dependencies=("${!1}")

  counter=$((counter+1))

  # If the counter is equal to 1, this is the installer dependency check. Otherwise, its the main dependency checks.
  if [[ "${counter}" == 1 ]]; then
    echo -e "  ${INFO} Installer Dependency checks..."
  else
    echo -e "  ${INFO} Main Dependency checks..."
  fi

  # array containing all dependencies which need to be installed
  # NOTE: We may be able to use this installArray in the future to create a list of package that were
  # installed by us, and remove only the installed packages, and not the entire list.
  declare -a installArray

  # Debian-family based package install - debconf will download the entire package list
  # so we just create an array of packages not currently installed to cut down on the
  # amount of download traffic.
  if command -v debconf-apt-progress &> /dev/null; then

    # For each dependency, check if it needs to be installed.
    for i in "${dependencies[@]}"; do
      echo -ne "  ${INFO} Checking for $i..."

      # If the package is already installed, nothing needs to be done.
      if dpkg-query -W -f='${Status}' "${i}" 2>/dev/null | grep "ok installed" &> /dev/null; then
        echo -e "${OVER}  ${TICK} Checking for $i"

      # Otherwise add it to the list of packages to be installed.
      else
        echo -e "${OVER}  ${INFO} Checking for $i (will be installed)"
        installArray+=("${i}")
      fi
    done

    # If there are dependencies which are not yet installed, install them.
    if [[ "${#installArray[@]}" -gt 0 ]]; then
      test_dpkg_lock
      debconf-apt-progress -- "${PKG_INSTALL[@]}" "${installArray[@]}"
    fi

  # Fedora-family
  else

    # For each dependency, check if it needs to be installed.
    for i in "${dependencies[@]}"; do
      echo -ne "  ${INFO} Checking for $i..."

      # If the package is already installed, nothing needs to be done.
      if "${PKG_MANAGER}" -q list installed "${i}" &> /dev/null; then
        echo -e "${OVER}  ${TICK} Checking for $i"

      # Otherwise add it to the list of packages to be installed.
      else
        echo -e "${OVER}  ${INFO} Checking for $i (will be installed)"
        installArray+=("${i}")
      fi
    done

    # If there are dependencies which are not yet installed, install them.
    if [[ "${#installArray[@]}" -gt 0 ]]; then
      "${PKG_INSTALL[@]}" "${installArray[@]}" &> /dev/null
    fi
  fi

  echo ""
  return 0
}

# Installs the web dashboard.
install_pihole_web() {

  echo ""
  echo "  ${INFO} Installing blocking page..."

  # Create a message to tell the user what is currently happening and display it.
  local msg="Creating directory for blocking page, and copying files"
  echo -ne "  ${INFO} ${msg}..."

  # Install the directory and the blockpage
  install -d /var/www/html/pihole
  install -D "${PI_HOLE_LOCAL_REPO}"/advanced/{index,blockingpage}.* /var/www/html/pihole/

  # Remove superseded file
  if [[ -e "/var/www/html/pihole/index.js" ]]; then
    rm "/var/www/html/pihole/index.js"
  fi

  echo -e "${OVER}  ${TICK} ${msg}"

  local msg="Backing up index.lighttpd.html"
  echo -ne "  ${INFO} ${msg}..."

  # If the default index file exists, back it up.
  if [[ -f "/var/www/html/index.lighttpd.html" ]]; then
    mv /var/www/html/index.lighttpd.html /var/www/html/index.lighttpd.orig
    echo -e "${OVER}  ${TICK} ${msg}"

  # Otherwise, don't do anything.
  else
    echo -e "${OVER}  ${CROSS} ${msg}
      No default index.lighttpd.html file found... not backing up"
  fi

  # Install the sudoers file.
  echo ""
  local msg="Installing sudoer file"
  echo -ne "  ${INFO} ${msg}..."

  # Make the sudoers.d directory if it doesn't exist and copy in the Pi-hole suoders file.
  mkdir -p /etc/sudoers.d/
  cp "${PI_HOLE_LOCAL_REPO}"/advanced/pihole.sudo /etc/sudoers.d/pihole

  # Add the lighttpd user (OS dependent) to the sudoers file.
  echo "${LIGHTTPD_USER} ALL=NOPASSWD: /usr/local/bin/pihole" >> /etc/sudoers.d/pihole

  # Fedora-family - If the Web server user is lighttpd, allow executing Pi-hole via sudo.
  # Usually /usr/local/bin is not permitted as directory for sudoable programs
  if [[ "$LIGHTTPD_USER" == "lighttpd" ]]; then
    echo "Defaults secure_path = /sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin" >> /etc/sudoers.d/pihole
  fi

  # Set strict permissions on Pi-hole's sudoers file.
  chmod 0440 /etc/sudoers.d/pihole

  echo -e "${OVER}  ${TICK} ${msg}"
}

# Sets up cron to update ad sources, flush the query log and keep Pi-hole up to date.
install_cron() {

  # Create a message to tell the user what is currently happening and display it.
  local msg="Installing latest Cron script"
  echo ""
  echo -ne "  ${INFO} ${msg}..."

  # Copy the cron file over from the local repo.
  cp "${PI_HOLE_LOCAL_REPO}"/advanced/pihole.cron /etc/cron.d/pihole

  # Randomize gravity update time
  sed -i "s/59 1 /$((1 + RANDOM % 58)) $((3 + RANDOM % 2))/" /etc/cron.d/pihole
  # Randomize update checker time
  sed -i "s/59 17/$((1 + RANDOM % 58)) $((12 + RANDOM % 8))/" /etc/cron.d/pihole

  echo -e "${OVER}  ${TICK} ${msg}"
}

# Runs Gravity. Gravity is a very important script as it aggregates all of the domains into a single HOSTS formatted list,
# which is what Pi-hole needs to begin blocking ads
run_gravity() {
  # Run gravity in the current shell.
  { /opt/pihole/gravity.sh --force; }
}

# Checks if the Pi-hole user pihole exists and creates it if it does not.
create_pihole_user() {

  # Create a message to tell the user what is currently happening and display it.
  local msg="Checking for user 'pihole'"
  echo -ne "  ${INFO} ${msg}..."

  # If the user pihole exists, display success.
  if id -u pihole &> /dev/null; then
    echo -ne "${OVER}  ${TICK} ${msg}"

  # Otherwise, create it.
  else
    echo -ne "${OVER}  ${CROSS} ${msg}"
    local msg="Creating user 'pihole'"
    echo -ne "  ${INFO} ${msg}..."

    useradd -r -s /usr/sbin/nologin pihole

    echo -ne "${OVER}  ${TICK} ${msg}"
  fi
}

# Configures the local firewall to allow HTTP and DNS traffic.
configure_firewall() {
  echo ""

  # If the firewall-cmd command is available, configure the firewall using it.
  if firewall-cmd --state &> /dev/null; then

    # Ask if the user wants to install Pi-hole's default firewall rules.
    whiptail --title "Firewall in use" --yesno "We have detected a running firewall\\n\\nPi-hole currently requires HTTP and DNS port access.\\n\\n\\n\\nInstall Pi-hole default firewall rules?" ${R} ${C} || \
      # If the user choses to not install the firewall, return.
      { echo -e "  ${INFO} Not installing firewall rulesets."; return 0; }

    echo -e "  ${TICK} Configuring FirewallD for httpd and pihole-FTL"

    # Allow HTTP and DNS traffic
    firewall-cmd --permanent --add-service=http --add-service=dns

    # Reload the firewall to apply these changes
    firewall-cmd --reload

  # Otherwise, check for the kernel module ip_tables and the iptables command to prevent failure.
  elif modinfo ip_tables &> /dev/null && command -v iptables &> /dev/null; then

    # If the chain Policy is not ACCEPT or last Rule is not ACCEPT
    # then check and insert our Rules above the DROP/REJECT Rule.
    if iptables -S INPUT | head -n1 | grep -qv '^-P.*ACCEPT$' || iptables -S INPUT | tail -n1 | grep -qv '^-\(A\|P\).*ACCEPT$'; then

      # Ask if the user wants to install Pi-hole's default firewall rules.
      whiptail --title "Firewall in use" --yesno "We have detected a running firewall\\n\\nPi-hole currently requires HTTP and DNS port access.\\n\\n\\n\\nInstall Pi-hole default firewall rules?" ${R} ${C} || \
        # If the user choses to not install the firewall, return.
        { echo -e "  ${INFO} Not installing firewall rulesets."; return 0; }

      echo -e "  ${TICK} Installing new IPTables firewall rulesets"

      # Check chain first, otherwise a new rule will duplicate old ones
      iptables -C INPUT -p tcp -m tcp --dport 80 -j ACCEPT &> /dev/null || iptables -I INPUT 1 -p tcp -m tcp --dport 80 -j ACCEPT
      iptables -C INPUT -p tcp -m tcp --dport 53 -j ACCEPT &> /dev/null || iptables -I INPUT 1 -p tcp -m tcp --dport 53 -j ACCEPT
      iptables -C INPUT -p udp -m udp --dport 53 -j ACCEPT &> /dev/null || iptables -I INPUT 1 -p udp -m udp --dport 53 -j ACCEPT
      iptables -C INPUT -p tcp -m tcp --dport 4711:4720 -i lo -j ACCEPT &> /dev/null || iptables -I INPUT 1 -p tcp -m tcp --dport 4711:4720 -i lo -j ACCEPT

    fi

  # Otherwise, no firewall is running so just exit.
  else
    echo -e "  ${INFO} No active firewall detected.. skipping firewall configuration"
  fi
}

# Exports the various variables set during installation to the file ${SETUP_VARS}, such that they
# can be reused when updating or reinstalling Pi-hole later on.
final_exports() {

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

  # If the setup variable file exists, update the variables in the file.
  if [[ -e "${SETUP_VARS}" ]]; then
    sed -i.update.bak '/PIHOLE_INTERFACE/d;/IPV4_ADDRESS/d;/IPV6_ADDRESS/d;/PIHOLE_DNS_1/d;/PIHOLE_DNS_2/d;/QUERY_LOGGING/d;/INSTALL_WEB_SERVER/d;/INSTALL_WEB_INTERFACE/d;/LIGHTTPD_ENABLED/d;' "${SETUP_VARS}"
  fi

  # Export the variables to the ${SETUP_VARS} file.
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
  }>> "${SETUP_VARS}"

  # Bring in the current settings and the functions to manipulate them.
  source "${SETUP_VARS}"
  source "${PI_HOLE_LOCAL_REPO}/advanced/Scripts/webpage.sh"

  # Look for DNS server settings which would have to be reapplied
  ProcessDNSSettings

  # Look for DHCP server settings which would have to be reapplied
  ProcessDHCPSettings
}

# Configures logrotate to rotate the log files for Pi-hole and FTL.
install_logrotate() {

  # Create a message to tell the user what is currently happening and display it.
  local msg="Installing latest logrotate script"
  echo ""
  echo -ne "  ${INFO} ${msg}..."

  # Copy the file over from the local repo.
  cp "${PI_HOLE_LOCAL_REPO}"/advanced/logrotate /etc/pihole/logrotate

  # Different operating systems have different user / group settings for logrotate.
  # This makes it impossible to create a static logrotate file that will work with e.g.
  # Rasbian and Ubuntu at the same time. Hence, we have to customize the logrotate
  # script here in order to reflect the local properties of the /var/log directory
  local logusergroup="$(stat -c '%U %G' /var/log)"

  # If the variable has a value,
  if [[ ! -z "${logusergroup}" ]]; then
    sed -i "s/# su #/su ${logusergroup}/g;" /etc/pihole/logrotate
  fi

  echo -e "${OVER}  ${TICK} ${msg}"
}

# Update variable names in ${SETUP_VARS} to account for refactored variables. At some point
# in the future this list can be pruned. For now we'll need it to ensure updates don't break.
account_for_refactor() {
  sed -i 's/piholeInterface/PIHOLE_INTERFACE/g' "${SETUP_VARS}"
  sed -i 's/IPv4_address/IPV4_ADDRESS/g' "${SETUP_VARS}"
  sed -i 's/IPv4addr/IPV4_ADDRESS/g' "${SETUP_VARS}"
  sed -i 's/IPv6_address/IPV6_ADDRESS/g' "${SETUP_VARS}"
  sed -i 's/piholeIPv6/IPV6_ADDRESS/g' "${SETUP_VARS}"
  sed -i 's/piholeDNS1/PIHOLE_DNS_1/g' "${SETUP_VARS}"
  sed -i 's/piholeDNS2/PIHOLE_DNS_2/g' "${SETUP_VARS}"
  sed -i 's/^INSTALL_WEB=/INSTALL_WEB_INTERFACE=/' "${SETUP_VARS}"

  # Add 'INSTALL_WEB_SERVER', if its not been applied already: https://github.com/pi-hole/pi-hole/pull/2115
  if ! grep -q '^INSTALL_WEB_SERVER=' "${SETUP_VARS}"; then
    local webserver_installed=false
    if grep -q '^INSTALL_WEB_INTERFACE=true' "${SETUP_VARS}"; then
      webserver_installed=true
    fi
    echo -e "INSTALL_WEB_SERVER=$webserver_installed" >> "${SETUP_VARS}"
  fi
}

# Installs the base files for Pi-hole and the web interface, if the user has chosen to install it.
install_pihole() {

  # Create the pihole user
  create_pihole_user

  # If the user wants to install the web interface, prepare its directory set up the web server.
  if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then

    # Make the Web directory if necessary.
    if [[ ! -d "/var/www/html" ]]; then
      mkdir -p /var/www/html
    fi

    # If the user chose to install the lighttpd web server, install it.
    if [[ "${INSTALL_WEB_SERVER}" == true ]]; then

      # Make the LIGHTTPD_USER own the web server directory and set the permissions.
      chown "${LIGHTTPD_USER}":"${LIGHTTPD_GROUP}" /var/www/html
      chmod 775 /var/www/html

      # Give the pihole user access to the web server group.
      usermod -a -G "${LIGHTTPD_GROUP}" pihole

      # If the lighttpd command is executable, enable fastcgi and fastcgi-php.
      if [[ -x "$(command -v lighty-enable-mod)" ]]; then
        lighty-enable-mod fastcgi fastcgi-php > /dev/null || true

      # Otherwise, show a warning instructing the user to install them.
      else
        echo -e  "  ${INFO} Warning: 'lighty-enable-mod' utility not found
        Please ensure fastcgi is enabled if you experience issues\\n"
      fi
    fi
  fi

  # If old ${SETUP_VARS} are to be used, account for refactoring.
  if [[ "${USE_UPDATE_VARS}" == true ]]; then
    account_for_refactor
  fi

  # Install base files, the web interface and configuration files.
  install_scripts
  install_configs

  # If the user wants to install the dashboard, install it.
  if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then
    install_pihole_web
  fi

  # Install the cron file and logrotate.
  install_cron
  install_logrotate

  # Install FTL.
  detect_ftl || echo -e "  ${CROSS} FTL Engine not installed"

  # Configure the firewall.
  if [[ "${USE_UPDATE_VARS}" == false ]]; then
    configure_firewall
  fi

  # Update ${SETUP_VARS} with any variables that may or may not have been changed during the installation.
  final_exports
}

# Determines if SELinux is installed and informs the user about possible problems if it is.
check_selinux() {

  # If the getenforce command exists, SELinux is installed.
  if command -v getenforce &> /dev/null; then

    # Store the current mode in a variable.
    enforceMode=$(getenforce)
    echo -e "\\n  ${INFO} SELinux mode detected: ${enforceMode}"

    # If it's enforcing, explain Pi-hole does not support it yet.
    if [[ "${enforceMode}" == "Enforcing" ]]; then
      # Show a dialog explaining it to the user and ask if the installation should proceed.
      whiptail --defaultno --title "SELinux Enforcing Detected" --yesno "SELinux is being ENFORCED on your system! \\n\\nPi-hole currently does not support SELinux, but you may still continue with the installation.\\n\\nNote: Web Admin will not be fully functional unless you set your policies correctly\\n\\nContinue installing Pi-hole?" ${R} ${C} || \
        # If the user choses to cancel, exit the installer.
        { echo -e "\\n  ${COL_LIGHT_RED}SELinux Enforcing detected, exiting installer${COL_NC}"; exit 1; }
      echo -e "  ${INFO} Continuing installation with SELinux Enforcing
  ${INFO} Please refer to official SELinux documentation to create a custom policy"
    fi
  fi
}

# Displays the final ddialog to the user and displays the server's addresses as well as the web interface password, if the web interface has been installed.
display_final_message() {

  # If a password as been provided as parameter, use it.
  local pwstring=""
  if [[ "${#1}" -gt 0 ]] ; then
    pwstring="$1"

  # Otherwise, try getting the password from ${SETUP_VARS}.
  elif [[ $(grep 'WEBPASSWORD' -c /etc/pihole/setupVars.conf) -gt 0 ]]; then
    pwstring="unchanged"

  # If no password was given, set a variable for later evaluation.
  else
    pwstring="NOT SET"
  fi

  # If the user installed the dashboard, prepare a message to displaz the dashboard information
  # to the user.
  if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then
      additional="View the web interface at http://pi.hole/admin or http://${IPV4_ADDRESS%/*}/admin

Your Admin Webpage login password is ${pwstring}"
  fi

  # Display the final completion message to the user.
  whiptail --msgbox --backtitle "Make it so." --title "Installation Complete!" "Configure your devices to use the Pi-hole as their DNS server using:

IPv4:    ${IPV4_ADDRESS%/*}
IPv6:    ${IPV6_ADDRESS:-"Not Configured"}

If you set a new IP address, you should restart the Pi.

The install log is in /etc/pihole.

${additional}" "${R}" "${C}"
}

# Displays a dialog giving the user the choice between repairing, updating or reconfiguring Pi-hole.
update_dialogs() {

  # Set the first option depending on whether the -r "reconfigure" parameter was supplied.
  local opt1a=""
  local opt1b=""
  local strAdd=""
  if [[ "${RECONFIGURE}" = true ]]; then
    opt1a="Repair"
    opt1b="This will retain existing settings"
    strAdd="You will remain on the same version"
  else
    opt1a="Update"
    opt1b="This will retain existing settings."
    strAdd="You will be updated to the latest version."
  fi
  # The second option is always reconfiguration.
  local opt2a="Reconfigure"
  local opt2b="This will reset your Pi-hole and allow you to enter new settings."

  # Display the dialog to the user and store his choice in a variable.
  local updateChoice=$(whiptail --title "Existing Install Detected!" --menu "\\n\\nWe have detected an existing install.\\n\\nPlease choose from the following options: \\n($strAdd)" ${R} ${C} 2 \
    "${opt1a}"  "${opt1b}" \
    "${opt2a}"  "${opt2b}" 3>&2 2>&1 1>&3) || cancel

  # Set the USE_UPDATE_VARS variable according to the user's choice.
  case "${updateCmd}" in
    # repair/update
    "${opt1a}" )
      echo -e "  ${INFO} ${opt1a} option selected"
      USE_UPDATE_VARS=true
      ;;
    # reconfigure
    "${opt2a}" )
      echo -e "  ${INFO} ${opt2a} option selected"
      USE_UPDATE_VARS=false
      ;;
    esac
}

# Checks if a given FTL download exists on the ftl.pi-hole.net server.
#  $1: the download to be checked
check_download_exists() {
  local download="${1}"

  local status=$(curl --head --silent "https://ftl.pi-hole.net/${1}" | head -n 1)
  if grep -q "404" <<< "$status"; then
    return 1
  else
    return 0
  fi
}

# Adds all upstream branches to a shallow local git repository.
#  $1: the directory containing the local git repository
fully_fetch_repo() {
  local directory="${1}"

  cd "${directory}" || return 1
  if is_repo "${directory}"; then
    git remote set-branches origin '*' || return 1
    git fetch --quiet || return 1
    return 0
  else
    return 1
  fi
}

# Gets a list of all available remote branches of a local git repository.
#  $1: the directory containing the local git repository
get_available_branches() {
  local directory="${1}"

  # Try moving to the given directory or return an error if it does not work.
  cd "${directory}" || return 1

  # Get reachable remote branches, but store STDERR as STDOUT variable
  local output=$( { git remote show origin | grep 'tracked' | sed 's/tracked//;s/ //g'; } 2>&1 )
  echo "${output}"
}

# Fetches, checks out and pulls a given remote branch of a local git repository.
#  $1: the directory containing the local git repository
#  $2: the remote branch's name
fetch_checkout_pull_branch() {
  local directory="${1}"
  local branch="${2}"

  # Try moving to the given directory or return an error if it does not work.
  cd "${directory}" || return 1

  # Set the reference for the requested branch, fetch, check it put and pull it.
  git remote set-branches origin "${branch}" || return 1
  git stash --all --quiet &> /dev/null || true
  git clean --quiet --force -d || true
  git fetch --quiet || return 1
  checkout_pull_branch "${directory}" "${branch}" || return 1
}

# Checks out and pulls a given remote branch of a local git repository.
#  $1: the directory containing the local git repository
#  $2: the remote branch's name
checkout_pull_branch() {
  local directory="${1}"
  local branchh="${2}"
  local oldbranch

  # Create a message to tell the user what is currently happening and display it.
  local msg="Switching to branch: '${branch}' from '${oldbranch}'"
  echo -ne "  ${INFO} ${msg}..."

  # Try moving to the given directory or return an error if it does not work.
  cd "${directory}" || return 1

  local oldbranch="$(git symbolic-ref HEAD)"

  git checkout "${branch}" --quiet || return 1
  echo -e "${OVER}  ${TICK} $msg"

  git_pull=$(git pull || return 1)

  if [[ "$git_pull" == *"up-to-date"* ]]; then
    echo -e "  ${INFO} ${git_pull}"
  else
    echo -e "$git_pull\\n"
  fi

  return 0
}

# Either resets the local git repository ${PI_HOLE_LOCAL_REPO} if a reconfiguration is in process (${RECONFIGURE} is true)
# or clones/updates the repository otherwise.
clone_or_update_repos() {

  # If the user wants to reconfigure an existing installation, update all local repositories.
  if [[ "${RECONFIGURE}" == true ]]; then
    echo "  ${INFO} Performing reconfiguration, skipping download of local repos"

    # Reset the core repository to get rid of all local changes.
    reset_repo "${PI_HOLE_LOCAL_REPO}" || \
      { echo -e "  ${COL_LIGHT_RED}Unable to reset ${PI_HOLE_LOCAL_REPO}, exiting installer${COL_NC}"; \
        exit 1; \
      }

    # If the Web interface was installed, reset its repository too.
    if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then
      reset_repo "${WEB_INTERFACE_DIR}" || \
        { echo -e "  ${COL_LIGHT_RED}Unable to reset ${WEB_INTERFACE_DIR}, exiting installer${COL_NC}"; \
          exit 1; \
        }
    fi

  # Otherwise, a repair is happening and the local repositories need to be replaced.
  else

    # Clone the core repository, deleting the old local repository in the process.
    get_git_files "${PI_HOLE_LOCAL_REPO}" "${PIHOLE_GIT_URL}" || \
      { echo -e "  ${COL_LIGHT_RED}Unable to clone ${PIHOLE_GIT_URL} into ${PI_HOLE_LOCAL_REPO}, unable to continue${COL_NC}"; \
        exit 1; \
      }

    # If the web interface was installed, clone its repository as well.
    if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then
      get_git_files "${WEB_INTERFACE_DIR}" "${WEB_INTERFACE_GIT_URL}" || \
        { echo -e "  ${COL_LIGHT_RED}Unable to clone ${WEB_INTERFACE_GIT_URL} into ${WEB_INTERFACE_DIR}, exiting installer${COL_NC}"; \
          exit 1; \
        }
    fi
  fi
}

# Downloads the FTL binary to a random temporary directory and install it.
install_ftl() {
  local binary="${1}"

  # Create a message to tell the user what is currently happening and display it.
  local msg="Downloading and Installing FTL"
  echo -ne "  ${INFO} ${msg}..."

  # Find the latest version tag for FTL
  local latestTag=$(curl -sI https://github.com/pi-hole/FTL/releases/latest | grep "Location" | awk -F '/' '{print $NF}')

  # Tags should always start with v. If it does not, an error occured and we need to exit.
  if [[ ! "${latestTag}" == v* ]]; then
    echo -e "${OVER}  ${CROSS} ${msg}"
    echo -e "  ${COL_LIGHT_RED}Error: Unable to get latest release location from GitHub${COL_NC}"
    return 1
  fi

  # Move into the temporary ftl directory.
  pushd "$(mktemp -d)" > /dev/null || { echo "Unable to make temporary directory for FTL binary download"; return 1; }

  # Always replace pihole-FTL.service.
  install -T -m 0755 "${PI_HOLE_LOCAL_REPO}/advanced/pihole-FTL.service" "/etc/init.d/pihole-FTL"

  # Determine which git branch to copy.
  local ftlBranch
  if [[ -f "/etc/pihole/ftlbranch" ]];then
    ftlBranch=$(</etc/pihole/ftlbranch)
  else
    ftlBranch="master"
  fi

  # Construct the URL to download the FTL binary with respect to the tag and branch.
  local url
  if [[ "${ftlBranch}" == "master" ]];then
    url="https://github.com/pi-hole/FTL/releases/download/${latestTag%$'\r'}"
  else
    url="https://ftl.pi-hole.net/${ftlBranch}"
  fi

  # Attempt to download the file and install it if the download was successful.
  if curl -sSL --fail "${url}/${binary}" -o "${binary}"; then
    # get sha1 of the binary we just downloaded for verification.
    curl -sSL --fail "${url}/${binary}.sha1" -o "${binary}.sha1"

    # If we downloaded binary file (as opposed to text),
    if sha1sum --status --quiet -c "${binary}".sha1; then
      echo -n "transferred... "

      # Stop FTL.
      stop_service pihole-FTL &> /dev/null

      # Install the new version with the correct permissions
      install -T -m 0755 "${binary}" /usr/bin/pihole-FTL

      # Move back into the original directory the user was in.
      popd > /dev/null || { echo "Unable to return to original directory after FTL binary download."; return 1; }

      # Install the FTL service.
      echo -e "${OVER}  ${TICK} ${msg}"

      # dnsmasq can now be stopped and disabled if it exists.
      if which dnsmasq > /dev/null; then
        if check_service_active "dnsmasq";then
          echo "  ${INFO} FTL can now resolve DNS Queries without dnsmasq running separately"
          stop_service dnsmasq
          disable_service dnsmasq
        fi
      fi

      #ensure /etc/dnsmasq.conf contains `conf-dir=/etc/dnsmasq.d`
      local confdir="conf-dir=/etc/dnsmasq.d"
      local conffile="/etc/dnsmasq.conf"

      if ! grep -q "$confdir" "$conffile"; then
          echo "$confdir" >> "$conffile"
      fi

      return 0

    # Otherwise, a corrupted file was downloaded. Show an return an error.
    else
      # Move back into the original directory the user was in.
      popd > /dev/null || { echo "Unable to return to original directory after FTL binary download."; return 1; }

      echo -e "${OVER}  ${CROSS} ${msg}"
      echo -e "  ${COL_LIGHT_RED}Error: Download of binary from Github failed${COL_NC}"
      return 1
    fi

  # If the download failed completely, the URL could not be found. Show and return an error.
  else
    # Move back into the original directory the user was in.
    popd > /dev/null || { echo "Unable to return to original directory after FTL binary download."; return 1; }

    echo -e "${OVER}  ${CROSS} ${msg}"
    echo -e "  ${COL_LIGHT_RED}Error: URL not found${COL_NC}"
    return 1
  fi
}

# Determines the name of the right FTL binary for this OS.
get_ftl_binary_name() {

  # Create a message to tell the user what is currently happening and display it.
  local msg="Detecting architecture"
  echo -ne "  ${INFO} ${msg}..."

  # Store architecture in a variable.
  local architecture=$(uname -m)

  # Depending on the given architecture, determine the correct binary to download.

  # ARM / AARCH
  FTL_BINARY=""
  if [[ "${architecture}" == "arm"* || "${architecture}" == *"aarch"* ]]; then

    local rev=$(uname -m | sed "s/[^0-9]//g;")

    local lib=$(ldd /bin/ls | grep -E '^\s*/lib' | awk '{ print $1 }')

    # AARCH64
    if [[ "${lib}" == "/lib/ld-linux-aarch64.so.1" ]]; then
      echo -e "${OVER}  ${TICK} Detected ARM-aarch64 architecture"
      FTL_BINARY="pihole-FTL-aarch64-linux-gnu"

    # ARMhf
    elif [[ "${lib}" == "/lib/ld-linux-armhf.so.3" ]]; then

      # ARMv7+
      if [[ "${rev}" -gt 6 ]]; then
        echo -e "${OVER}  ${TICK} Detected ARM-hf architecture (armv7+)"
        FTL_BINARY="pihole-FTL-arm-linux-gnueabihf"

      # ARMv6 or lower
      else
        echo -e "${OVER}  ${TICK} Detected ARM-hf architecture (armv6 or lower) Using ARM binary"
        # set the binary to be used
        FTL_BINARY="pihole-FTL-arm-linux-gnueabi"
      fi

    # ARM
    else
      echo -e "${OVER}  ${TICK} Detected ARM architecture"
      FTL_BINARY="pihole-FTL-arm-linux-gnueabi"
    fi

  # PowerPC
  elif [[ "${architecture}" == "ppc" ]]; then
    echo -e "${OVER}  ${TICK} Detected PowerPC architecture"
    FTL_BINARY="pihole-FTL-powerpc-linux-gnu"

  # x86_64
  elif [[ "${architecture}" == "x86_64" ]]; then
    echo -e "${OVER}  ${TICK} Detected x86_64 architecture"
    FTL_BINARY="pihole-FTL-linux-x86_64"

  # x86_32 or something else
  else

    # If the architecture is not x86_32, try using the x86_32 binary, but show a warning.
    if [[ ! "${architecture}" == "i686" ]]; then
      echo -e "${OVER}  ${CROSS} ${str}...
      ${COL_LIGHT_RED}Not able to detect architecture (unknown: ${architecture}), trying 32bit executable${COL_NC}
      Contact Pi-hole Support if you experience issues (e.g: FTL not running)"

    else
      echo -e "${OVER}  ${TICK} Detected 32bit (i686) architecture"
    fi

    FTL_BINARY="pihole-FTL-linux-x86_32"
  fi
}

# Checks if there exists an update for the currently used FTL binary. Returns true if an update
# is available, if no local FTL binary was found or if the local binary is corrupted.
check_ftl_update()
{
  get_ftl_binary_name

  #In the next section we check to see if FTL is already installed (in case of pihole -r).
  #If the installed version matches the latest version, then check the installed sha1sum of the binary vs the remote sha1sum. If they do not match, then download
  echo -e "  ${INFO} Checking for existing FTL binary..."

  local ftlLoc=$(which pihole-FTL 2>/dev/null)

  # Determine which FTL branch we are on.
  local ftlBranch
  if [[ -f "/etc/pihole/ftlbranch" ]];then
    ftlBranch=$(</etc/pihole/ftlbranch)
  else
    ftlBranch="master"
  fi

   # If dnsmasq exists and is running at this point, force reinstall of FTL Binary and return.
  if which dnsmasq > /dev/null; then
    if check_service_active "dnsmasq";then
      return 0
    fi
  fi

  # If we are not on the master branch...
  if [[ ! "${ftlBranch}" == "master" ]]; then

    # Check whether or not the binary for this FTL branch actually exists. If not, then there is no update!
    local path="${ftlBranch}/${binary}"

    # Check if there exists a download for the FTL binary of the given branch. If there is not,
    # abort and return an error.
    # shellcheck disable=SC1090
    if ! check_download_exists "$path"; then
      echo -e "  ${INFO} Branch \"${ftlBranch}\" is not available.\\n  ${INFO} Use ${COL_LIGHT_GREEN}pihole checkout ftl [branchname]${COL_NC} to switch to a valid branch."
      return 2
    fi

    # If we already have a pihole-FTL binary downloaded...
    if [[ "${ftlLoc}" ]]; then

      # Alt branches don't have a tagged version against them. Compare the checksums of the local
      # binary and the remote one, to determine if we should download the remote version.
      local remoteSha1=$(curl -sSL --fail "https://ftl.pi-hole.net/${ftlBranch}/${binary}.sha1" | cut -d ' ' -f 1)
      local localSha1=$(sha1sum "$(which pihole-FTL)" | cut -d ' ' -f 1)

        # If the checksums differ, the local binary is corrupt. Return that an update is available.
      if [[ "${remoteSha1}" != "${localSha1}" ]]; then
        echo -e "  ${INFO} Checksums do not match, downloading from ftl.pi-hole.net."
        return 0

      # Otherwise, return that no update is needed.
      else
        echo -e "  ${INFO} Checksum of installed binary matches remote. No need to download!"
        return 1
      fi

    # If no binary is present, return true.
    else
      return 0
    fi

  # If we are on the master branch...
  else

    # If a local FTL binary exists, check if it out of date or corrupted.
    if [[ "${ftlLoc}" ]]; then

      # Get the version tags of the local binary and the most recent remote binary.
      local localVersion=$(/usr/bin/pihole-FTL tag)
      local ftlLatestTag=$(curl -sI https://github.com/pi-hole/FTL/releases/latest | grep 'Location' | awk -F '/' '{print $NF}' | tr -d '\r\n')

      # If the version of the local binary and the most recent remote binary differ, return true.
      if [[ "${localVersion}" != "${ftlLatestTag}" ]]; then
        return 0

      # Otherwise check if the local binary has been corrupted.
      else
        echo -e "  ${INFO} Latest FTL Binary already installed (${ftlLatestTag}). Confirming Checksum..."

        # Get the checksums of the local and the remote binary.
        local localSha1=$(sha1sum "$(which pihole-FTL)" | cut -d ' ' -f 1)
        local remoteSha1=$(curl -sSL --fail "https://github.com/pi-hole/FTL/releases/download/${localVersion%$'\r'}/${binary}.sha1" | cut -d ' ' -f 1)

        # If the checksums differ, the local binary is corrupt. Return that an update is available.
        if [[ "${remoteSha1}" != "${localSha1}" ]]; then
          echo -e "  ${INFO} Corruption detected..."
          return 0

        # Otherwise, return that no update is needed.
        else
          echo -e "  ${INFO} Checksum correct. No need to download!"
          return 1
        fi
      fi

    # Otherwise, return true.
    else
      return 0
    fi
  fi
}

# Determines if this system is a suitable FTL platform and install FTL if it is.
detect_ftl() {
  echo ""
  echo -e "  ${INFO} FTL Checks..."

  # If FTL is not installed or an update is available, install/update it.
  if check_ftl_update ; then
    install_ftl "${FTL_BINARY}" || return 1
  fi

  echo ""
}

# Creates a tempirary log file to store the installation log.
make_temporary_log() {
  # Create a random temporary file for the log
  local tempLog=$(mktemp /tmp/pihole_temp.XXXXXX)

  # Open handle 3 for templog
  # https://stackoverflow.com/questions/18460186/writing-outputs-to-log-file-and-console
  exec 3>"$tempLog"

  # Delete templog, but allow for addressing via file handle
  # This lets us write to the log without having a temporary file on the drive, which
  # is meant to be a security measure so there is not a lingering file on the drive during the install process
  rm "$tempLog"
}

# Copies the installation's output into the install log.
copy_to_install_log() {
  # Copy the contents of file descriptor 3 into the install log.
  # Since we use color codes such as '\e[1;33m', they need to be removed using sed.
  sed 's/\[[0-9;]\{1,5\}m//g' < /proc/$$/fd/3 > "${INSTALL_LOG_LOC}"
}


#------- Main

# Runs the setup.
main() {

  # The current user must be root to install. Check if that is the case.

  # Create a message to tell the user what is currently happening and display it.
  local msg="Root user check"
  echo -ne "  ${INFO} ${msg}..."

  echo ""

  # If the user's id is not equal to zero, they are not root.
  if [[ "${EUID}" -ne 0 ]]; then

   # They do not have enough privileges, so let the user know.
    echo -e "  ${CROSS} ${str}
      ${COL_LIGHT_RED}Script called with non-root privileges${COL_NC}
      The Pi-hole requires elevated privileges to install and run
      Please check the installer for any concerns regarding this requirement
      Make sure to download this script from a trusted source\\n"

    # Check if sudo is installed, to gain higher priviliges.
    echo -ne "  ${INFO} Sudo utility check"

    # If the sudo command exists, try executing the installer with sudo.
    if command -v sudo &> /dev/null; then
      echo -e "${OVER}  ${TICK} Sudo utility check"

      exec curl -sSL https://raw.githubusercontent.com/pi-hole/pi-hole/master/automated%20install/basic-install.sh | sudo bash "$@"
      exit $?

    # Otherwise, let them know they need to run it as root and exit.
    else
      echo -e "${OVER}  ${CROSS} Sudo utility check
      Sudo is needed for the Web Interface to run pihole commands\\n
  ${COL_LIGHT_RED}Please re-run this installer as root${COL_NC}"
      exit 1
    fi
  fi

  # Otherwise, continue.
  echo -e "  ${TICK} ${str}"

  # Show the Pi-hole logo so people know it's genuine since the logo and name are trademarked
  show_ascii_berry

  # Create the temporary log to write to both the console and the install log.
  make_temporary_log

  # Check for supported distribution
  distro_check

  # If the setup variable file ${SETUP_VARS} exists...
  if [[ -f "${SETUP_VARS}" ]]; then
    # if it's running unattended,
    if [[ "${RUN_UNATTENDED}" == true ]]; then
      echo -e "  ${INFO} Performing unattended setup, no whiptail dialogs will be displayed"
      # Use the setup variables
      USE_UPDATE_VARS=true
    # Otherwise,
    else
      # show the available options (repair/reconfigure)
      update_dialogs
    fi
  fi

  # Start the installer
  # Verify there is enough disk space for the install
  if [[ "${SKIP_SPACE_CHECK}" == true ]]; then
    echo -e "  ${INFO} Skipping free disk space verification"
  else
    verify_free_disk_space
  fi

  # Update package cache
  update_package_cache || exit 1

  # Notify user of package availability
  notify_package_updates_available

  # Install packages used by this installation script
  install_dependent_packages INSTALLER_DEPS[@]

   # Check if SELinux is Enforcing
  check_selinux

  if [[ "${USE_UPDATE_VARS}" == false ]]; then
    # Display welcome dialogs
    welcome_dialogs
    # Create directory for Pi-hole storage
    mkdir -p /etc/pihole/
    # Determine available interfaces
    get_available_interfaces
    # Find interfaces and let the user choose one
    choose_interface
    # Decide what upstream DNS Servers to use
    set_dns
    # Give the user a choice of blocklists to include in their install. Or not.
    choose_blocklists
    # Let the user decide if they want to block ads over IPv4 and/or IPv6
    use_ipv4_andor_ipv6
    # Let the user decide if they want the web interface to be installed automatically
    set_admin_flag
    # Let the user decide if they want query logging enabled...
    set_logging
  else
    # Source ${SETUP_VARS} to use predefined user variables in the functions
    source "${SETUP_VARS}"
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

  if [[ -x "$(command -v systemctl)" ]]; then
    # Value will either be 1, if true, or 0
    LIGHTTPD_ENABLED=$(systemctl is-enabled lighttpd | grep -c 'enabled' || true)
  else
    # Value will either be 1, if true, or 0
    LIGHTTPD_ENABLED=$(service lighttpd status | awk '/Loaded:/ {print $0}' | grep -c 'enabled' || true)
  fi

  # Install and log everything to a file
  install_pihole | tee -a /proc/$$/fd/3

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
        echo "WEBPASSWORD=$(HashPassword ${pw})" >> "${SETUP_VARS}"
    fi
  fi

  echo -e "  ${INFO} Restarting services..."
  # Start services

  # If the Web server was installed,
  if [[ "${INSTALL_WEB_SERVER}" == true ]]; then

    if [[ "${LIGHTTPD_ENABLED}" == "1" ]]; then
      start_service lighttpd
      enable_service lighttpd
    else
      echo -e "  ${INFO} Lighttpd is disabled, skipping service restart"
    fi
  fi

  # Enable FTL
  start_service pihole-FTL
  enable_service pihole-FTL

  # Download and compile the aggregated block list
  run_gravity

  # Force an update of the updatechecker
  . /opt/pihole/updatecheck.sh
  . /opt/pihole/updatecheck.sh x remote

  #
  if [[ "${USE_UPDATE_VARS}" == false ]]; then
      display_final_message "${pw}"
  fi

  # If the Web interface was installed,
  if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then
    # If there is a password,
    if (( "${#pw}" > 0 )) ; then
      # display the password
      echo -e "  ${INFO} Web Interface password: ${COL_LIGHT_GREEN}${pw}${COL_NC}
      This can be changed using 'pihole -a -p'\\n"
    fi
  fi

  #
  if [[ "${USE_UPDATE_VARS}" == false ]]; then
    # If the Web interface was installed,
    if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then
      echo -e "  View the web interface at http://pi.hole/admin or http://${IPV4_ADDRESS%/*}/admin"
      echo ""
    fi
    # Explain to the user how to use Pi-hole as their DNS server
    echo "  You may now configure your devices to use the Pi-hole as their DNS server"
    [[ -n "${IPV4_ADDRESS%/*}" ]] && echo -e "  ${INFO} Pi-hole DNS (IPv4): ${IPV4_ADDRESS%/*}"
    [[ -n "${IPV6_ADDRESS}" ]] && echo -e "  ${INFO} Pi-hole DNS (IPv6): ${IPV6_ADDRESS}"
    echo -e "  If you set a new IP address, please restart the server running the Pi-hole"
    #
    INSTALL_TYPE="Installation"
  else
    #
    INSTALL_TYPE="Update"
  fi

  # Display where the log file is
  echo -e "\\n  ${INFO} The install log is located at: ${INSTALL_LOG_LOC}
  ${COL_LIGHT_GREEN}${INSTALL_TYPE} Complete! ${COL_NC}"

  if [[ "${INSTALL_TYPE}" == "Update" ]]; then
    echo ""
    /usr/local/bin/pihole version --current
  fi
}

#
if [[ "${PH_TEST}" != true ]] ; then
  main "$@"
fi
