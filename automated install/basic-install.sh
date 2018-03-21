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

# We store several other folders and
webInterfaceGitUrl="https://github.com/pi-hole/AdminLTE.git"
webInterfaceDir="/var/www/html/admin"
piholeGitUrl="https://github.com/pi-hole/pi-hole.git"
PI_HOLE_LOCAL_REPO="/etc/.pihole"
# These are the names of pi-holes files, stored in an array
PI_HOLE_FILES=(chronometer list piholeDebug piholeLogFlush setupLCD update version gravity uninstall webpage)
# This folder is where the Pi-hole scripts will be installed
PI_HOLE_INSTALL_DIR="/opt/pihole"
useUpdateVars=false

# Pi-hole needs an IP address; to begin, these variables are empty since we don't know what the IP is until
# this script can run
IPV4_ADDRESS=""
IPV6_ADDRESS=""
# By default, query logging is enabled and the dashboard is set to be installed
QUERY_LOGGING=true
INSTALL_WEB=true


# Find the rows and columns will default to 80x24 if it can not be detected
screen_size=$(stty size 2>/dev/null || echo 24 80)
rows=$(echo "${screen_size}" | awk '{print $1}')
columns=$(echo "${screen_size}" | awk '{print $2}')

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

# Compatibility
distro_check() {
# If apt-get is installed, then we know it's part of the Debian family
if command -v apt-get &> /dev/null; then
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
  # Debian 7 doesn't have iproute2 so if the dry run install is successful,
  if ${PKG_MANAGER} install --dry-run iproute2 > /dev/null 2>&1; then
    # we can install it
    iproute_pkg="iproute2"
  # Otherwise,
  else
    # use iproute
    iproute_pkg="iproute"
  fi
  # We prefer the php metapackage if it's there
  if ${PKG_MANAGER} install --dry-run php > /dev/null 2>&1; then
    phpVer="php"
  # If not,
  else
    # fall back on the php5 packages
    phpVer="php5"
  fi
  # We also need the correct version for `php-sqlite` (which differs across distros)
  if ${PKG_MANAGER} install --dry-run ${phpVer}-sqlite3 > /dev/null 2>&1; then
    phpSqlite="sqlite3"
  else
    phpSqlite="sqlite"
  fi
  # Since our install script is so large, we need several other programs to successfuly get a machine provisioned
  # These programs are stored in an array so they can be looped through later
  INSTALLER_DEPS=(apt-utils dialog debconf dhcpcd5 git ${iproute_pkg} whiptail)
  # Pi-hole itself has several dependencies that also need to be installed
  PIHOLE_DEPS=(bc cron curl dnsmasq dnsutils iputils-ping lsof netcat sudo unzip wget idn2 sqlite3)
  # The Web dashboard has some that also need to be installed
  # It's useful to separate the two since our repos are also setup as "Core" code and "Web" code
  PIHOLE_WEB_DEPS=(lighttpd ${phpVer}-common ${phpVer}-cgi ${phpVer}-${phpSqlite})
  # The Web server user,
  LIGHTTPD_USER="www-data"
  # group,
  LIGHTTPD_GROUP="www-data"
  # and config file
  LIGHTTPD_CFG="lighttpd.conf.debian"
  # The DNS server user
  DNSMASQ_USER="dnsmasq"

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
elif command -v rpm &> /dev/null; then
  # Then check if dnf or yum is the package manager
  if command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
  else
    PKG_MANAGER="yum"
  fi

  # Fedora and family update cache on every PKG_INSTALL call, no need for a separate update.
  UPDATE_PKG_CACHE=":"
  PKG_INSTALL=(${PKG_MANAGER} install -y)
  PKG_COUNT="${PKG_MANAGER} check-update | egrep '(.i686|.x86|.noarch|.arm|.src)' | wc -l"
  INSTALLER_DEPS=(dialog git iproute net-tools newt procps-ng)
  PIHOLE_DEPS=(bc bind-utils cronie curl dnsmasq findutils nmap-ncat sudo unzip wget libidn2 psmisc)
  PIHOLE_WEB_DEPS=(lighttpd lighttpd-fastcgi php php-common php-cli php-pdo)
  # EPEL (https://fedoraproject.org/wiki/EPEL) is required for lighttpd on CentOS
  if grep -qi 'centos' /etc/redhat-release; then
    INSTALLER_DEPS=("${INSTALLER_DEPS[@]}" "epel-release");
  fi
    LIGHTTPD_USER="lighttpd"
    LIGHTTPD_GROUP="lighttpd"
    LIGHTTPD_CFG="lighttpd.conf.fedora"
    DNSMASQ_USER="nobody"

# If neither apt-get or rmp/dnf are found
else
  # it's not an OS we can support,
  echo -e "  ${CROSS} OS distribution not supported"
  # so exit the installer
  exit
fi
}

# A function for checking if a folder is a git repository
is_repo() {
  # Use a named, local variable instead of the vague $1, which is the first arguement passed to this function
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
    # Use git to check if the folder is a repo
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
  echo -ne "  ${INFO} ${str}..."
  # If the directory exists,
  if [[ -d "${directory}" ]]; then
    # delete everything in it so git can clone into it
    rm -rf "${directory}"
  fi
  # Clone the repo and return the return code from this command
  git clone -q --depth 1 "${remoteRepo}" "${directory}" &> /dev/null || return $?
  # Show a colored message showing it's status
  echo -e "${OVER}  ${TICK} ${str}"
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
  echo -ne "  ${INFO} ${str}..."
  # Stash any local commits as they conflict with our working code
  git stash --all --quiet &> /dev/null || true # Okay for stash failure
  git clean --quiet --force -d || true # Okay for already clean directory
  # Pull the latest commits
  git pull --quiet &> /dev/null || return $?
  # Show a completion message
  echo -e "${OVER}  ${TICK} ${str}"
  # Move back into the oiginal directory
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
  # A local varible containing the message to be displayed
  local str="Check for existing repository in ${1}"
  # Show the message
  echo -ne "  ${INFO} ${str}..."
  # Check if the directory is a repository
  if is_repo "${directory}"; then
    # Show that we're checking it
    echo -e "${OVER}  ${TICK} ${str}"
    # Update the repo, returning an error message on failure
    update_repo "${directory}" || { echo -e "\\n  ${COL_LIGHT_RED}Error: Could not update local repository. Contact support.${COL_NC}"; exit 1; }
  # If it's not a .git repo,
  else
    # Show an error
    echo -e "${OVER}  ${CROSS} ${str}"
    # Attempt to make the repository, showing an error on falure
    make_repo "${directory}" "${remoteRepo}" || { echo -e "\\n  ${COL_LIGHT_RED}Error: Could not update local repository. Contact support.${COL_NC}"; exit 1; }
  fi
  # echo a blank line
  echo ""
  # and return success?
  return 0
}

# Reset a repo to get rid of any local changed
resetRepo() {
  # Use named varibles for arguments
  local directory="${1}"
  # Move into the directory
  cd "${directory}" &> /dev/null || return 1
  # Store the message in a varible
  str="Resetting repository within ${1}..."
  # Show the message
  echo -ne "  ${INFO} ${str}"
  # Use git to remove the local changes
  git reset --hard &> /dev/null || return $?
  # And show the status
  echo -e "${OVER}  ${TICK} ${str}"
  # Returning success anyway?
  return 0
}

# We need to know the IPv4 information so we can effectively setup the DNS server
# Without this information, we won't know where to Pi-hole will be found
find_IPv4_information() {
  # Named, local variables
  local route
  # Find IP used to route to outside world by checking the the route to Google's public DNS server
  route=$(ip route get 8.8.8.8)
  # Use awk to strip out just the interface device as it is used in future commands
  IPv4dev=$(awk '{for (i=1; i<=NF; i++) if ($i~/dev/) print $(i+1)}' <<< "${route}")
  # Get just the IP address
  IPv4bare=$(awk '{print $7}' <<< "${route}")
  # Append the CIDR notation to the IP address
  IPV4_ADDRESS=$(ip -o -f inet addr show | grep "${IPv4bare}" |  awk '{print $4}' | awk 'END {print}')
  # Get the default gateway (the way to reach the Internet)
  IPv4gw=$(awk '{print $3}' <<< "${route}")

}

# Get available interfaces that are UP
get_available_interfaces() {
  # There may be more than one so it's all stored in a variable
  availableInterfaces=$(ip --oneline link show up | grep -v "lo" | awk '{print $2}' | cut -d':' -f1 | cut -d'@' -f1)
}

# A function for displaying the dialogs the user sees when first running the installer
welcomeDialogs() {
  # Display the welcome dialog using an approriately sized window via the calculation conducted earlier in the script
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
  # Reqired space in KB
  local required_free_kilobytes=51200
  # Calculate existing free space on this machine
  local existing_free_kilobytes
  existing_free_kilobytes=$(df -Pk | grep -m1 '\/$' | awk '{print $4}')

  # If the existing space is not an integer,
  if ! [[ "${existing_free_kilobytes}" =~ ^([0-9])+$ ]]; then
    # show an error that we can't determine the free space
    echo -e "  ${CROSS} ${str}
      Unknown free disk space!
      We were unable to determine available free disk space on this system.
      You may override this check, however, it is not recommended
      The option '${COL_LIGHT_RED}--i_do_not_follow_recommendations${COL_NC}' can override this
      e.g: curl -L https://install.pi-hole.net | bash /dev/stdin ${COL_LIGHT_RED}<option>${COL_NC}"
    # exit with an error code
    exit 1
  # If there is insufficient free disk space,
  elif [[ "${existing_free_kilobytes}" -lt "${required_free_kilobytes}" ]]; then
    # show an error message
    echo -e "  ${CROSS} ${str}
      Your system disk appears to only have ${existing_free_kilobytes} KB free
      It is recommended to have a minimum of ${required_free_kilobytes} KB to run the Pi-hole"
    # if the vcgencmd command exists,
    if command -v vcgencmd &> /dev/null; then
      # it's probably a Raspbian install, so show a message about expanding the filesystem
      echo "      If this is a new install you may need to expand your disk
      Run 'sudo raspi-config', and choose the 'expand file system' option
      After rebooting, run this installation again
      e.g: curl -L https://install.pi-hole.net | bash"
    fi
    # Show there is not enough free space
    echo -e "\\n      ${COL_LIGHT_RED}Insufficient free space, exiting...${COL_NC}"
    # and exit with an error
    exit 1
  # Otherwise,
  else
    # Show that we're running a disk space check
    echo -e "  ${TICK} ${str}"
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
  interfaceCount=$(echo "${availableInterfaces}" | wc -l)

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
      # If the user chooses Canel, exit
      { echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}"; exit 1; }
      # For each interface
      for desiredInterface in ${chooseInterfaceOptions}; do
        # Set the one the user selected as the interface to use
        PIHOLE_INTERFACE=${desiredInterface}
        # and show this information to the user
        echo -e "  ${INFO} Using interface: $PIHOLE_INTERFACE"
      done
  fi
}

# This lets us prefer ULA addresses over GUA
# This caused problems for some users when their ISP changed their IPv6 addresses
# See https://github.com/pi-hole/pi-hole/issues/1473#issuecomment-301745953
testIPv6() {
  # first will contain fda2 (ULA)
  first="$(cut -f1 -d":" <<< "$1")"
  # value1 will contain 253 which is the decimal value corresponding to 0xfd
  value1=$(( (0x$first)/256 ))
  # will contain 162 which is the decimal value corresponding to 0xa2
  value2=$(( (0x$first)%256 ))
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
    echo -e "  ${INFO} Found IPv6 ULA address, using it for blocking IPv6 ads"
  # Otherwise, if the GUA_ADDRESS has a value,
  elif [[ ! -z "${GUA_ADDRESS}" ]]; then
    # Let the user know
    echo -e "  ${INFO} Found IPv6 GUA address, using it for blocking IPv6 ads"
    # And assign it to the global variable
    IPV6_ADDRESS="${GUA_ADDRESS}"
  # If none of those work,
  else
    # explain that IPv6 blocking will not be used
    echo -e "  ${INFO} Unable to find IPv6 ULA/GUA address, IPv6 adblocking will not be enabled"
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
  choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty) || { echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}"; exit 1; }
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
    echo -e "  ${INFO} IPv4 address: ${IPV4_ADDRESS}"
    echo -e "  ${INFO} IPv6 address: ${IPV6_ADDRESS}"
  # If neither protocol is selected,
  if [[ ! "${useIPv4}" ]] && [[ ! "${useIPv6}" ]]; then
    # Show an error in red
    echo -e "  ${COL_LIGHT_RED}Error: Neither IPv4 or IPv6 selected${COL_NC}"
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
      echo -e "  ${INFO} Your static IPv4 address: ${IPV4_ADDRESS}"

      # Ask for the gateway
      IPv4gw=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 gateway (router)" --inputbox "Enter your desired IPv4 default gateway" ${r} ${c} "${IPv4gw}" 3>&1 1>&2 2>&3) || \
      # Cancelling gateway settings window
      { ipSettingsCorrect=False; echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}"; exit 1; }
      echo -e "  ${INFO} Your static IPv4 gateway: ${IPv4gw}"

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

# dhcpcd is very annoying,
setDHCPCD() {
  # but we can append these lines to dhcpcd.conf to enable a static IP
  echo "interface ${PIHOLE_INTERFACE}
  static ip_address=${IPV4_ADDRESS}
  static routers=${IPv4gw}
  static domain_name_servers=127.0.0.1" | tee -a /etc/dhcpcd.conf >/dev/null
}

setStaticIPv4() {
  # Local, named variables
  local IFCFG_FILE
  local IPADDR
  local CIDR
  # For the Debian family, if dhcpcd.conf exists,
  if [[ -f "/etc/dhcpcd.conf" ]]; then
    # check if the IP is already in the file
    if grep -q "${IPV4_ADDRESS}" /etc/dhcpcd.conf; then
      echo -e "  ${INFO} Static IP already configured"
    # If it's not,
    else
      # set it using our function
      setDHCPCD
      # Then use the ip command to immediately set the new address
      ip addr replace dev "${PIHOLE_INTERFACE}" "${IPV4_ADDRESS}"
      # Also give a warning that the user may need to reboot their system
      echo -e "  ${TICK} Set IP address to ${IPV4_ADDRESS%/*}
      You may need to restart after the install is complete"
    fi
  # If it's not Debian, check if it's the Fedora family by checking for the file below
  elif [[ -f "/etc/sysconfig/network-scripts/ifcfg-${PIHOLE_INTERFACE}" ]];then
    # If it exists,
    IFCFG_FILE=/etc/sysconfig/network-scripts/ifcfg-${PIHOLE_INTERFACE}
    # check if the desired IP is already set
    if grep -q "${IPV4_ADDRESS}" "${IFCFG_FILE}"; then
      echo -e "  ${INFO} Static IP already configured"
    # Otherwise,
    else
      # Put the IP in variables without the CIDR notation
      IPADDR=$(echo "${IPV4_ADDRESS}" | cut -f1 -d/)
      CIDR=$(echo "${IPV4_ADDRESS}" | cut -f2 -d/)
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
      if command -v nmcli &> /dev/null && nmcli general status &> /dev/null; then
        # Tell NetworkManagler to read our new sysconfig file
        nmcli con load "${IFCFG_FILE}" > /dev/null
      fi
      # Show a warning that the user may need to restart
      echo -e "  ${TICK} Set IP address to ${IPV4_ADDRESS%/*}
      You may need to restart after the install is complete"
    fi
  # If all that fails,
  else
    # show an error and exit
    echo -e "  ${INFO} Warning: Unable to locate configuration file to set static IPv4 address"
    exit 1
  fi
}

# Check an IP address to see if it is a valid one
valid_ip() {
  # Local, named variables
  local ip=${1}
  local stat=1

  # If the IP matches the format xxx.xxx.xxx.xxx,
  if [[ "${ip}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    # Save the old Interfal Field Separator in a variable
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
      Norton ""
      Comodo ""
      DNSWatch ""
      Quad9 ""
      FamilyShield ""
      Custom "")
  # In a whiptail dialog, show the options
  DNSchoices=$(whiptail --separate-output --menu "Select Upstream DNS Provider. To use your own, select Custom." ${r} ${c} 7 \
    "${DNSChooseOptions[@]}" 2>&1 >/dev/tty) || \
    # exit if Cancel is selected
    { echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}"; exit 1; }

  # Display the selection
  echo -ne "  ${INFO} Using "
  # Depending on the user's choice, set the GLOBAl variables to the IP of the respective provider
  case ${DNSchoices} in
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
    Custom)
      # Until the DNS settings are selected,
      until [[ "${DNSSettingsCorrect}" = True ]]; do
      #
      strInvalid="Invalid"
      # If the first
      if [[ ! "${PIHOLE_DNS_1}" ]]; then
        # and second upstream servers do not exist
        if [[ ! "${PIHOLE_DNS_2}" ]]; then
          #
          prePopulate=""
        # Otherwise,
        else
          #
          prePopulate=", ${PIHOLE_DNS_2}"
        fi
      #
      elif  [[ "${PIHOLE_DNS_1}" ]] && [[ ! "${PIHOLE_DNS_2}" ]]; then
        #
        prePopulate="${PIHOLE_DNS_1}"
      #
      elif [[ "${PIHOLE_DNS_1}" ]] && [[ "${PIHOLE_DNS_2}" ]]; then
        #
        prePopulate="${PIHOLE_DNS_1}, ${PIHOLE_DNS_2}"
      fi

      # Dialog for the user to enter custom upstream servers
      piholeDNS=$(whiptail --backtitle "Specify Upstream DNS Provider(s)"  --inputbox "Enter your desired upstream DNS provider(s), seperated by a comma.\\n\\nFor example '8.8.8.8, 8.8.4.4'" ${r} ${c} "${prePopulate}" 3>&1 1>&2 2>&3) || \
      { echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}"; exit 1; }
      #
      PIHOLE_DNS_1=$(echo "${piholeDNS}" | sed 's/[, \t]\+/,/g' | awk -F, '{print$1}')
      PIHOLE_DNS_2=$(echo "${piholeDNS}" | sed 's/[, \t]\+/,/g' | awk -F, '{print$2}')
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
      # Othwerise,
      else
        # Show the settings
        if (whiptail --backtitle "Specify Upstream DNS Provider(s)" --title "Upstream DNS Provider(s)" --yesno "Are these settings correct?\\n    DNS Server 1:   $PIHOLE_DNS_1\\n    DNS Server 2:   ${PIHOLE_DNS_2}" ${r} ${c}); then
        # and break from the loop since the servers are vaid
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
  LogToggleCommand=(whiptail --separate-output --radiolist "Do you want to log queries?\\n (Disabling will render graphs on the Admin page useless):" ${r} ${c} 6)
  # The default selection is on
  LogChooseOptions=("On (Recommended)" "" on
      Off "" off)
  # Get the user's choice
  LogChoices=$("${LogToggleCommand[@]}" "${LogChooseOptions[@]}" 2>&1 >/dev/tty) || (echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}" && exit 1)
    case ${LogChoices} in
      # If it's on
      "On (Recommended)")
        echo -e "  ${INFO} Logging On."
        # Set the GLOBAL variable to true so we know what they selected
        QUERY_LOGGING=true
        ;;
      # Othwerise, it's off,
      Off)
        echo -e "  ${INFO} Logging Off."
        # So set it to false
        QUERY_LOGGING=false
        ;;
    esac
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
  WebChoices=$("${WebToggleCommand[@]}" "${WebChooseOptions[@]}" 2>&1 >/dev/tty) || (echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}" && exit 1)
    # Depending on their choice
    case ${WebChoices} in
      "On (Recommended)")
        echo -e "  ${INFO} Web Interface On"
        # Set it to true
        INSTALL_WEB=true
        ;;
      Off)
        echo -e "  ${INFO} Web Interface Off"
        # or false
        INSTALL_WEB=false
        ;;
    esac
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
    echo -ne "  ${INFO} Existing dnsmasq.conf found..."
    # If gravity.list is found within this file, we presume it's from older versions on Pi-hole,
    if grep -q ${dnsmasq_pihole_id_string} ${dnsmasq_conf}; then
      echo " it is from a previous Pi-hole install."
      echo -ne "  ${INFO} Backing up dnsmasq.conf to dnsmasq.conf.orig..."
      # so backup the original file
      mv -f ${dnsmasq_conf} ${dnsmasq_conf_orig}
      echo -e "${OVER}  ${TICK} Backing up dnsmasq.conf to dnsmasq.conf.orig..."
      echo -ne "  ${INFO} Restoring default dnsmasq.conf..."
      # and replace it with the default
      cp ${dnsmasq_original_config} ${dnsmasq_conf}
      echo -e "${OVER}  ${TICK} Restoring default dnsmasq.conf..."
    # Otherwise,
    else
      # Don't to anything
      echo " it is not a Pi-hole file, leaving alone!"
    fi
  else
    # If a file cannot be found,
    echo -ne "  ${INFO} No dnsmasq.conf found... restoring default dnsmasq.conf..."
    # restore the default one
    cp ${dnsmasq_original_config} ${dnsmasq_conf}
    echo -e "${OVER}  ${TICK} No dnsmasq.conf found... restoring default dnsmasq.conf..."
  fi

  echo -en "  ${INFO} Copying 01-pihole.conf to /etc/dnsmasq.d/01-pihole.conf..."
  # Copy the new Pi-hole DNS config file into the dnsmasq.d directory
  cp ${dnsmasq_pihole_01_snippet} ${dnsmasq_pihole_01_location}
  echo -e "${OVER}  ${TICK} Copying 01-pihole.conf to /etc/dnsmasq.d/01-pihole.conf"
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
  echo -ne "  ${INFO} ${str}..."

  # Clear out script files from Pi-hole scripts directory.
  clean_existing "${PI_HOLE_INSTALL_DIR}" "${PI_HOLE_FILES[@]}"

  # Install files from local core repository
  if is_repo "${PI_HOLE_LOCAL_REPO}"; then
    # move into the directory
    cd "${PI_HOLE_LOCAL_REPO}"
    # Install the scripts by:
    #  -o setting the owner to the user
    #  -Dm755 create all leading components of destiantion except the last, then copy the source to the destiantion and setting the permissions to 755
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
    echo -e "${OVER}  ${TICK} ${str}"
 # Otherwise,
  else
    # Show an error and exit
    echo -e "${OVER}  ${CROSS} ${str}
  ${COL_LIGHT_RED}Error: Local repo ${PI_HOLE_LOCAL_REPO} not found, exiting installer${COL_NC}"
    exit 1
  fi
}

# Install the configs from PI_HOLE_LOCAL_REPO to their various locations
installConfigs() {
  echo ""
  echo -e "  ${INFO} Installing configs from ${PI_HOLE_LOCAL_REPO}..."
  # Make sure Pi-hole's config files are in place
  version_check_dnsmasq

  # If the user chose to install the dashboard,
  if [[ "${INSTALL_WEB}" == true ]]; then
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

stop_service() {
  # Stop service passed in as argument.
  # Can softfail, as process may not be installed when this is called
  local str="Stopping ${1} service"
  echo ""
  echo -ne "  ${INFO} ${str}..."
  if command -v systemctl &> /dev/null; then
    systemctl stop "${1}" &> /dev/null || true
  else
    service "${1}" stop &> /dev/null || true
  fi
  echo -e "${OVER}  ${TICK} ${str}..."
}

# Start/Restart service passed in as argument
start_service() {
  # Local, named variables
  local str="Starting ${1} service"
  echo ""
  echo -ne "  ${INFO} ${str}..."
  # If systemctl exists,
  if command -v systemctl &> /dev/null; then
    # use that to restart the service
    systemctl restart "${1}" &> /dev/null
  # Otherwise,
  else
    # fall back to the service command
    service "${1}" restart &> /dev/null
  fi
  echo -e "${OVER}  ${TICK} ${str}"
}

# Enable service so that it will start with next reboot
enable_service() {
  # Local, named variables
  local str="Enabling ${1} service to start on reboot"
  echo ""
  echo -ne "  ${INFO} ${str}..."
  # If systemctl exists,
  if command -v systemctl &> /dev/null; then
    # use that to enable the service
    systemctl enable "${1}" &> /dev/null
  # Othwerwise,
  else
    # use update-rc.d to accomplish this
    update-rc.d "${1}" defaults &> /dev/null
  fi
  echo -e "${OVER}  ${TICK} ${str}"
}

update_package_cache() {
  # Running apt-get update/upgrade with minimal output can cause some issues with
  # requiring user input (e.g password for phpmyadmin see #218)

  # Update package cache on apt based OSes. Do this every time since
  # it's quick and packages can be updated at any time.

  # Local, named variables
  local str="Update local cache of available packages"
  echo ""
  echo -ne "  ${INFO} ${str}..."
  # Create a command from the package cache variable
  if eval "${UPDATE_PKG_CACHE}" &> /dev/null; then
    echo -e "${OVER}  ${TICK} ${str}"
  # Otherwise,
  else
    # show an error and exit
    echo -e "${OVER}  ${CROSS} ${str}"
    echo -ne "  ${COL_LIGHT_RED}Error: Unable to update package cache. Please try \"${UPDATE_PKG_CACHE}\"${COL_NC}"
    return 1
  fi
}

# Let user know if they have outdated packages on their system and
# advise them to run a package update at soonest possible.
notify_package_updates_available() {
  # Local, named variables
  local str="Checking ${PKG_MANAGER} for upgraded packages"
  echo -ne "\\n  ${INFO} ${str}..."
  # Store the list of packages in a variable
  updatesToInstall=$(eval "${PKG_COUNT}")

  if [[ -d "/lib/modules/$(uname -r)" ]]; then
    #
    if [[ "${updatesToInstall}" -eq 0 ]]; then
      #
      echo -e "${OVER}  ${TICK} ${str}... up to date!"
      echo ""
    else
      #
      echo -e "${OVER}  ${TICK} ${str}... ${updatesToInstall} updates available"
      echo -e "  ${INFO} ${COL_LIGHT_GREEN}It is recommended to update your OS after installing the Pi-hole! ${COL_NC}"
      echo ""
    fi
  else
    echo -e "${OVER}  ${CROSS} ${str}
      Kernel update detected. If the install fails, please reboot and try again\\n"
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
    echo -e "  ${INFO} Installer Dependency checks..."
  else
    #
    echo -e "  ${INFO} Main Dependency checks..."
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
  if command -v debconf-apt-progress &> /dev/null; then
    # For each package,
    for i in "${argArray1[@]}"; do
      echo -ne "  ${INFO} Checking for $i..."
      #
      if dpkg-query -W -f='${Status}' "${i}" 2>/dev/null | grep "ok installed" &> /dev/null; then
        #
        echo -e "${OVER}  ${TICK} Checking for $i"
      else
        #
        echo -e "${OVER}  ${INFO} Checking for $i (will be installed)"
        #
        installArray+=("${i}")
      fi
    done
    #
    if [[ "${#installArray[@]}" -gt 0 ]]; then
      #
      test_dpkg_lock
      #
      debconf-apt-progress -- "${PKG_INSTALL[@]}" "${installArray[@]}"
      return
    fi
      echo ""
      #
      return 0
  fi

  # Install Fedora/CentOS packages
  for i in "${argArray1[@]}"; do
    echo -ne "  ${INFO} Checking for $i..."
    #
    if ${PKG_MANAGER} -q list installed "${i}" &> /dev/null; then
      echo -e "${OVER}  ${TICK} Checking for $i"
    else
      echo -e "${OVER}  ${INFO} Checking for $i (will be installed)"
      #
      installArray+=("${i}")
    fi
  done
  #
  if [[ "${#installArray[@]}" -gt 0 ]]; then
    #
    "${PKG_INSTALL[@]}" "${installArray[@]}" &> /dev/null
    return
  fi
  echo ""
  return 0
}

# Create logfiles if necessary
CreateLogFile() {
  local str="Creating log and changing owner to dnsmasq"
  echo ""
  echo -ne "  ${INFO} ${str}..."
  # If the pihole log does not exist,
  if [[ ! -f "/var/log/pihole.log" ]]; then
    # Make it,
    touch /var/log/pihole.log
    # set the permissions,
    chmod 644 /var/log/pihole.log
    # and owners
    chown "${DNSMASQ_USER}":root /var/log/pihole.log
    echo -e "${OVER}  ${TICK} ${str}"
  # Otherwise,
  else
    # the file should already exist
    echo -e " ${COL_LIGHT_GREEN}log already exists!${COL_NC}"
  fi
}

# Install the Web interface dashboard
installPiholeWeb() {
  echo ""
  echo "  ${INFO} Installing blocking page..."

  local str="Creating directory for blocking page, and copying files"
  echo -ne "  ${INFO} ${str}..."
  # Install the directory
  install -d /var/www/html/pihole
  # and the blockpage
  install -D ${PI_HOLE_LOCAL_REPO}/advanced/{index,blockingpage}.* /var/www/html/pihole/

  # Remove superseded file
  if [[ -e "/var/www/html/pihole/index.js" ]]; then
    rm "/var/www/html/pihole/index.js"
  fi

  echo -e "${OVER}  ${TICK} ${str}"

  local str="Backing up index.lighttpd.html"
  echo -ne "  ${INFO} ${str}..."
  # If the default index file exists,
  if [[ -f "/var/www/html/index.lighttpd.html" ]]; then
    # back it up
    mv /var/www/html/index.lighttpd.html /var/www/html/index.lighttpd.orig
    echo -e "${OVER}  ${TICK} ${str}"
  # Othwerwise,
  else
    # don't do anything
    echo -e "${OVER}  ${CROSS} ${str}
      No default index.lighttpd.html file found... not backing up"
  fi

  # Install Sudoers file
  echo ""
  local str="Installing sudoer file"
  echo -ne "  ${INFO} ${str}..."
  # Make the .d directory if it doesn't exist
  mkdir -p /etc/sudoers.d/
  # and copy in the pihole sudoers file
  cp ${PI_HOLE_LOCAL_REPO}/advanced/pihole.sudo /etc/sudoers.d/pihole
  # Add lighttpd user (OS dependent) to sudoers file
  echo "${LIGHTTPD_USER} ALL=NOPASSWD: /usr/local/bin/pihole" >> /etc/sudoers.d/pihole

  # If the Web server user is lighttpd,
  if [[ "$LIGHTTPD_USER" == "lighttpd" ]]; then
    # Allow executing pihole via sudo with Fedora
    # Usually /usr/local/bin is not permitted as directory for sudoable programms
    echo "Defaults secure_path = /sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin" >> /etc/sudoers.d/pihole
  fi
  # Set the strict permissions on the file
  chmod 0440 /etc/sudoers.d/pihole
  echo -e "${OVER}  ${TICK} ${str}"
}

# Installs a cron file
installCron() {
  # Install the cron job
  local str="Installing latest Cron script"
  echo ""
  echo -ne "  ${INFO} ${str}..."
  # Copy the cron file over from the local repo
  cp ${PI_HOLE_LOCAL_REPO}/advanced/pihole.cron /etc/cron.d/pihole
  # Randomize gravity update time
  sed -i "s/59 1 /$((1 + RANDOM % 58)) $((3 + RANDOM % 2))/" /etc/cron.d/pihole
  # Randomize update checker time
  sed -i "s/59 17/$((1 + RANDOM % 58)) $((12 + RANDOM % 8))/" /etc/cron.d/pihole
  echo -e "${OVER}  ${TICK} ${str}"
}

# Gravity is a very important script as it aggregates all of the domains into a single HOSTS formatted list,
# which is what Pi-hole needs to begin blocking ads
runGravity() {
  echo ""
  echo -e "  ${INFO} Preparing to run gravity.sh to refresh hosts..."
  # If cached lists exist,
  if ls /etc/pihole/list* 1> /dev/null 2>&1; then
    echo -e "  ${INFO} Cleaning up previous install (preserving whitelist/blacklist)"
    # remove them
    rm /etc/pihole/list.*
  fi
  # If the default ad lists file exists,
  if [[ ! -e /etc/pihole/adlists.default ]]; then
    # copy it over from the local repo
    cp ${PI_HOLE_LOCAL_REPO}/adlists.default /etc/pihole/adlists.default
  fi
  echo -e "  ${INFO} Running gravity.sh"
  # Run gravity in the current shell
  { /opt/pihole/gravity.sh; }
}

# Check if the pihole user exists and create if it does not
create_pihole_user() {
  local str="Checking for user 'pihole'"
  echo -ne "  ${INFO} ${str}..."
  # If the user pihole exists,
  if id -u pihole &> /dev/null; then
    # just show a success
    echo -ne "${OVER}  ${TICK} ${str}"
  # Othwerwise,
  else
    echo -ne "${OVER}  ${CROSS} ${str}"
    local str="Creating user 'pihole'"
    echo -ne "  ${INFO} ${str}..."
    # create her with the useradd command
    useradd -r -s /usr/sbin/nologin pihole
    echo -ne "${OVER}  ${TICK} ${str}"
  fi
}

# Allow HTTP and DNS traffic
configureFirewall() {
  echo ""
  # If a firewall is running,
  if firewall-cmd --state &> /dev/null; then
    # ask if the user wants to install Pi-hole's default firwall rules
    whiptail --title "Firewall in use" --yesno "We have detected a running firewall\\n\\nPi-hole currently requires HTTP and DNS port access.\\n\\n\\n\\nInstall Pi-hole default firewall rules?" ${r} ${c} || \
    { echo -e "  ${INFO} Not installing firewall rulesets."; return 0; }
    echo -e "  ${TICK} Configuring FirewallD for httpd and dnsmasq"
    # Allow HTTP and DNS traffice
    firewall-cmd --permanent --add-service=http --add-service=dns
    # Reload the firewall to apply these changes
    firewall-cmd --reload
    return 0
  # Check for proper kernel modules to prevent failure
  elif modinfo ip_tables &> /dev/null && command -v iptables &> /dev/null; then
    # If chain Policy is not ACCEPT or last Rule is not ACCEPT
    # then check and insert our Rules above the DROP/REJECT Rule.
    if iptables -S INPUT | head -n1 | grep -qv '^-P.*ACCEPT$' || iptables -S INPUT | tail -n1 | grep -qv '^-\(A\|P\).*ACCEPT$'; then
      whiptail --title "Firewall in use" --yesno "We have detected a running firewall\\n\\nPi-hole currently requires HTTP and DNS port access.\\n\\n\\n\\nInstall Pi-hole default firewall rules?" ${r} ${c} || \
      { echo -e "  ${INFO} Not installing firewall rulesets."; return 0; }
      echo -e "  ${TICK} Installing new IPTables firewall rulesets"
      # Check chain first, otherwise a new rule will duplicate old ones
      iptables -C INPUT -p tcp -m tcp --dport 80 -j ACCEPT &> /dev/null || iptables -I INPUT 1 -p tcp -m tcp --dport 80 -j ACCEPT
      iptables -C INPUT -p tcp -m tcp --dport 53 -j ACCEPT &> /dev/null || iptables -I INPUT 1 -p tcp -m tcp --dport 53 -j ACCEPT
      iptables -C INPUT -p udp -m udp --dport 53 -j ACCEPT &> /dev/null || iptables -I INPUT 1 -p udp -m udp --dport 53 -j ACCEPT
      iptables -C INPUT -p tcp -m tcp --dport 4711:4720 -i lo -j ACCEPT &> /dev/null || iptables -I INPUT 1 -p tcp -m tcp --dport 4711:4720 -i lo -j ACCEPT
      return 0
    fi
  # Othwerwise,
  else
    # no firewall is running
    echo -e "  ${INFO} No active firewall detected.. skipping firewall configuration"
    # so just exit
    return 0
  fi
  echo -e "  ${INFO} Skipping firewall configuration"
}

#
finalExports() {
  # If the Web interface is not set to be installed,
  if [[ "${INSTALL_WEB}" == false ]]; then
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
    sed -i.update.bak '/PIHOLE_INTERFACE/d;/IPV4_ADDRESS/d;/IPV6_ADDRESS/d;/PIHOLE_DNS_1/d;/PIHOLE_DNS_2/d;/QUERY_LOGGING/d;/INSTALL_WEB/d;/LIGHTTPD_ENABLED/d;' "${setupVars}"
  fi
  # echo the information to the user
    {
  echo "PIHOLE_INTERFACE=${PIHOLE_INTERFACE}"
  echo "IPV4_ADDRESS=${IPV4_ADDRESS}"
  echo "IPV6_ADDRESS=${IPV6_ADDRESS}"
  echo "PIHOLE_DNS_1=${PIHOLE_DNS_1}"
  echo "PIHOLE_DNS_2=${PIHOLE_DNS_2}"
  echo "QUERY_LOGGING=${QUERY_LOGGING}"
  echo "INSTALL_WEB=${INSTALL_WEB}"
  echo "LIGHTTPD_ENABLED=${LIGHTTPD_ENABLED}"
    }>> "${setupVars}"

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
  echo ""
  echo -ne "  ${INFO} ${str}..."
  # Copy the file over from the local repo
  cp ${PI_HOLE_LOCAL_REPO}/advanced/logrotate /etc/pihole/logrotate
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
  echo -e "${OVER}  ${TICK} ${str}"
}

# Install base files and web interface
installPihole() {
  # Create the pihole user
  create_pihole_user

  # If the user wants to install the Web interface,
  if [[ "${INSTALL_WEB}" == true ]]; then
    if [[ ! -d "/var/www/html" ]]; then
      # make the Web directory if necessary
      mkdir -p /var/www/html
    fi
    # Set the owner and permissions
    chown ${LIGHTTPD_USER}:${LIGHTTPD_GROUP} /var/www/html
    chmod 775 /var/www/html
    # Give pihole access to the Web server group
    usermod -a -G ${LIGHTTPD_GROUP} pihole
    # If the lighttpd command is executable,
    if [[ -x "$(command -v lighty-enable-mod)" ]]; then
      # enable fastcgi and fastcgi-php
      lighty-enable-mod fastcgi fastcgi-php > /dev/null || true
    else
      # Othweise, show info about installing them
      echo -e  "  ${INFO} Warning: 'lighty-enable-mod' utility not found
      Please ensure fastcgi is enabled if you experience issues\\n"
    fi
  fi
  # Install scripts,
  installScripts
  # configs,
  installConfigs
  # and create the log file
  CreateLogFile
  # If the user wants to install the dashboard,
  if [[ "${INSTALL_WEB}" == true ]]; then
    # do so
    installPiholeWeb
  fi
  # Install the cron file
  installCron
  # Install the logrotate file
  installLogrotate
  # Check if FTL is installed
  FTLdetect || echo -e "  ${CROSS} FTL Engine not installed"
  # Configure the firewall
  configureFirewall

  #update setupvars.conf with any variables that may or may not have been changed during the install
  finalExports
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
}

updatePihole() {
  accountForRefactor
  # Install base files and web interface
  installScripts
  # Install config files
  installConfigs
  # Create the log file
  CreateLogFile
  # If the user wants to install the dasboard,
  if [[ "${INSTALL_WEB}" == true ]]; then
    # do so
    installPiholeWeb
  fi
  # Install the cron file
  installCron
  # Install logrotate
  installLogrotate
  # Detect if FTL is installed
  FTLdetect || echo -e "  ${CROSS} FTL Engine not installed."

  #update setupvars.conf with any variables that may or may not have been changed during the install
  finalExports

}


# SELinux
checkSelinux() {
  # If the getenforce command exists,
  if command -v getenforce &> /dev/null; then
    # Store the current mode in a variable
    enforceMode=$(getenforce)
    echo -e "\\n  ${INFO} SELinux mode detected: ${enforceMode}"

    # If it's enforcing,
    if [[ "${enforceMode}" == "Enforcing" ]]; then
      # Explain Pi-hole does not support it yet
      whiptail --defaultno --title "SELinux Enforcing Detected" --yesno "SELinux is being ENFORCED on your system! \\n\\nPi-hole currently does not support SELinux, but you may still continue with the installation.\\n\\nNote: Web Admin will not be fully functional unless you set your policies correctly\\n\\nContinue installing Pi-hole?" ${r} ${c} || \
        { echo -e "\\n  ${COL_LIGHT_RED}SELinux Enforcing detected, exiting installer${COL_NC}"; exit 1; }
      echo -e "  ${INFO} Continuing installation with SELinux Enforcing
  ${INFO} Please refer to official SELinux documentation to create a custom policy"
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
   if [[ "${INSTALL_WEB}" == true ]]; then
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
  # Othweise,
  else
    # set some variables with different values
    opt1a="Update"
    opt1b="This will retain existing settings."
    strAdd="You will be updated to the latest version."
  fi
  opt2a="Reconfigure"
  opt2b="This will allow you to enter new settings"

  # Display the information to the user
  UpdateCmd=$(whiptail --title "Existing Install Detected!" --menu "\\n\\nWe have detected an existing install.\\n\\nPlease choose from the following options: \\n($strAdd)" ${r} ${c} 2 \
  "${opt1a}"  "${opt1b}" \
  "${opt2a}"  "${opt2b}" 3>&2 2>&1 1>&3) || \
  { echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}"; exit 1; }

  # Set the variable based on if the user chooses
  case ${UpdateCmd} in
    # repair, or
    ${opt1a})
      echo -e "  ${INFO} ${opt1a} option selected"
      useUpdateVars=true
      ;;
    # reconfigure,
    ${opt2a})
      echo -e "  ${INFO} ${opt2a} option selected"
      useUpdateVars=false
      ;;
    esac
}

clone_or_update_repos() {
  # If the user wants to reconfigure,
  if [[ "${reconfigure}" == true ]]; then
    echo "  ${INFO} Performing reconfiguration, skipping download of local repos"
    # Reset the Core repo
    resetRepo ${PI_HOLE_LOCAL_REPO} || \
      { echo -e "  ${COL_LIGHT_RED}Unable to reset ${PI_HOLE_LOCAL_REPO}, exiting installer${COL_NC}"; \
        exit 1; \
      }
    # If the Web interface was installed,
    if [[ "${INSTALL_WEB}" == true ]]; then
      # reset it's repo
      resetRepo ${webInterfaceDir} || \
        { echo -e "  ${COL_LIGHT_RED}Unable to reset ${webInterfaceDir}, exiting installer${COL_NC}"; \
          exit 1; \
        }
    fi
  # Otherwise, a repair is happening
  else
    # so get git files for Core
    getGitFiles ${PI_HOLE_LOCAL_REPO} ${piholeGitUrl} || \
      { echo -e "  ${COL_LIGHT_RED}Unable to clone ${piholeGitUrl} into ${PI_HOLE_LOCAL_REPO}, unable to continue${COL_NC}"; \
        exit 1; \
      }
      # If the Web interface was installed,
      if [[ "${INSTALL_WEB}" == true ]]; then
        # get the Web git files
        getGitFiles ${webInterfaceDir} ${webInterfaceGitUrl} || \
        { echo -e "  ${COL_LIGHT_RED}Unable to clone ${webInterfaceGitUrl} into ${webInterfaceDir}, exiting installer${COL_NC}"; \
          exit 1; \
        }
      fi
  fi
}

# Download FTL binary to random temp directory and install FTL binary
FTLinstall() {
  # Local, named variables
  local binary="${1}"
  local latesttag
  local str="Downloading and Installing FTL"
  echo -ne "  ${INFO} ${str}..."

  # Find the latest version tag for FTL
  latesttag=$(curl -sI https://github.com/pi-hole/FTL/releases/latest | grep "Location" | awk -F '/' '{print $NF}')
  # Tags should always start with v, check for that.
  if [[ ! "${latesttag}" == v* ]]; then
    echo -e "${OVER}  ${CROSS} ${str}"
    echo -e "  ${COL_LIGHT_RED}Error: Unable to get latest release location from GitHub${COL_NC}"
    return 1
  fi

  # Move into the temp ftl directory
  pushd "$(mktemp -d)" || { echo "Unable to make temporary directory for FTL binary download"; return 1; }

  # Always replace pihole-FTL.service
  install -T -m 0755 "${PI_HOLE_LOCAL_REPO}/advanced/pihole-FTL.service" "/etc/init.d/pihole-FTL"

  # If the download worked,
  if curl -sSL --fail "https://github.com/pi-hole/FTL/releases/download/${latesttag%$'\r'}/${binary}" -o "${binary}"; then
    # get sha1 of the binary we just downloaded for verification.
    curl -sSL --fail "https://github.com/pi-hole/FTL/releases/download/${latesttag%$'\r'}/${binary}.sha1" -o "${binary}.sha1"

    # If we downloaded binary file (as opposed to text),
    if sha1sum --status --quiet -c "${binary}".sha1; then
      echo -n "transferred... "
      # Stop FTL
      stop_service pihole-FTL &> /dev/null
      # Install the new version with the correct permissions
      install -T -m 0755 "${binary}" /usr/bin/pihole-FTL
      # Move back into the original directory the user was in
      popd || { echo "Unable to return to original directory after FTL binary download."; return 1; }
      # Install the FTL service
      echo -e "${OVER}  ${TICK} ${str}"
      return 0
    # Otherise,
    else
      # the download failed, so just go back to the original directory
      popd || { echo "Unable to return to original directory after FTL binary download."; return 1; }
      echo -e "${OVER}  ${CROSS} ${str}"
      echo -e "  ${COL_LIGHT_RED}Error: Download of binary from Github failed${COL_NC}"
      return 1
    fi
  # Otherwise,
  else
    popd || { echo "Unable to return to original directory after FTL binary download."; return 1; }
    echo -e "${OVER}  ${CROSS} ${str}"
    # The URL could not be found
    echo -e "  ${COL_LIGHT_RED}Error: URL not found${COL_NC}"
    return 1
  fi
}

# Detect suitable FTL binary platform
FTLdetect() {
  echo ""
  echo -e "  ${INFO} FTL Checks..."

  # Local, named variables
  local machine
  local binary

  # Store architecture in a variable
  machine=$(uname -m)

  local str="Detecting architecture"
  echo -ne "  ${INFO} ${str}..."
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
      echo -e "${OVER}  ${TICK} Detected ARM-aarch64 architecture"
      # set the binary to be used
      binary="pihole-FTL-aarch64-linux-gnu"
    #
    elif [[ "${lib}" == "/lib/ld-linux-armhf.so.3" ]]; then
      #
      if [[ "${rev}" -gt 6 ]]; then
        echo -e "${OVER}  ${TICK} Detected ARM-hf architecture (armv7+)"
        # set the binary to be used
        binary="pihole-FTL-arm-linux-gnueabihf"
      # Otherwise,
      else
        echo -e "${OVER}  ${TICK} Detected ARM-hf architecture (armv6 or lower) Using ARM binary"
        # set the binary to be used
        binary="pihole-FTL-arm-linux-gnueabi"
      fi
    else
      echo -e "${OVER}  ${TICK} Detected ARM architecture"
      # set the binary to be used
      binary="pihole-FTL-arm-linux-gnueabi"
    fi
  elif [[ "${machine}" == "ppc" ]]; then
    # PowerPC
    echo -e "${OVER}  ${TICK} Detected PowerPC architecture"
    # set the binary to be used
    binary="pihole-FTL-powerpc-linux-gnu"
  elif [[ "${machine}" == "x86_64" ]]; then
    # 64bit
    echo -e "${OVER}  ${TICK} Detected x86_64 architecture"
    # set the binary to be used
    binary="pihole-FTL-linux-x86_64"
  else
    # Something else - we try to use 32bit executable and warn the user
    if [[ ! "${machine}" == "i686" ]]; then
      echo -e "${OVER}  ${CROSS} ${str}...
      ${COL_LIGHT_RED}Not able to detect architecture (unknown: ${machine}), trying 32bit executable${COL_NC}
      Contact Pi-hole Support if you experience issues (e.g: FTL not running)"
    else
      echo -e "${OVER}  ${TICK} Detected 32bit (i686) architecture"
    fi
    binary="pihole-FTL-linux-x86_32"
  fi

  #In the next section we check to see if FTL is already installed (in case of pihole -r).
  #If the installed version matches the latest version, then check the installed sha1sum of the binary vs the remote sha1sum. If they do not match, then download
  echo -e "  ${INFO} Checking for existing FTL binary..."

  local ftlLoc=$(which pihole-FTL 2>/dev/null)

  if [[ ${ftlLoc} ]]; then
    local FTLversion=$(/usr/bin/pihole-FTL tag)
	  local FTLlatesttag=$(curl -sI https://github.com/pi-hole/FTL/releases/latest | grep 'Location' | awk -F '/' '{print $NF}' | tr -d '\r\n')

	  if [[ "${FTLversion}" != "${FTLlatesttag}" ]]; then
		  # Install FTL
      FTLinstall "${binary}" || return 1
	  else
	    echo -e "  ${INFO} Latest FTL Binary already installed (${FTLlatesttag}). Confirming Checksum..."

	    local remoteSha1=$(curl -sSL --fail "https://github.com/pi-hole/FTL/releases/download/${FTLversion%$'\r'}/${binary}.sha1" | cut -d ' ' -f 1)
	    local localSha1=$(sha1sum "$(which pihole-FTL)" | cut -d ' ' -f 1)

	    if [[ "${remoteSha1}" != "${localSha1}" ]]; then
	      echo -e "  ${INFO} Corruption detected..."
	      FTLinstall "${binary}" || return 1
	    else
	      echo -e "  ${INFO} Checksum correct. No need to download!"
	    fi
	  fi
	else
	  # Install FTL
    FTLinstall "${binary}" || return 1
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
  echo ""

  # If the user's id is zero,
  if [[ "${EUID}" -eq 0 ]]; then
    # they are root and all is good
    echo -e "  ${TICK} ${str}"
    # Show the Pi-hole logo so people know it's genuine since the logo and name are trademarked
    show_ascii_berry
    make_temporary_log
  # Otherwise,
  else
    # They do not have enough privileges, so let the user know
    echo -e "  ${CROSS} ${str}
      ${COL_LIGHT_RED}Script called with non-root privileges${COL_NC}
      The Pi-hole requires elevated privileges to install and run
      Please check the installer for any concerns regarding this requirement
      Make sure to download this script from a trusted source\\n"
    echo -ne "  ${INFO} Sudo utility check"

    # If the sudo command exists,
    if command -v sudo &> /dev/null; then
      echo -e "${OVER}  ${TICK} Sudo utility check"
      # Download the install script and run it with admin rights
      exec curl -sSL https://raw.githubusercontent.com/pi-hole/pi-hole/master/automated%20install/basic-install.sh | sudo bash "$@"
      exit $?
    # Otherwise,
    else
      # Let them know they need to run it as root
      echo -e "${OVER}  ${CROSS} Sudo utility check
      Sudo is needed for the Web Interface to run pihole commands\\n
  ${COL_LIGHT_RED}Please re-run this installer as root${COL_NC}"
      exit 1
    fi
  fi

  # Check for supported distribution
  distro_check

  # Check arguments for the undocumented flags
  for var in "$@"; do
    case "$var" in
      "--reconfigure" ) reconfigure=true;;
      "--i_do_not_follow_recommendations" ) skipSpaceCheck=true;;
      "--unattended" ) runUnattended=true;;
    esac
  done

  # If the setup variable file exists,
  if [[ -f "${setupVars}" ]]; then
    # if it's running unattended,
    if [[ "${runUnattended}" == true ]]; then
      echo -e "  ${INFO} Performing unattended setup, no whiptail dialogs will be displayed"
      # Use the setup variables
      useUpdateVars=true
    # Otherwise,
    else
      # show the available options (repair/reconfigure)
      update_dialogs
    fi
  fi

  # Start the installer
  # Verify there is enough disk space for the install
  if [[ "${skipSpaceCheck}" == true ]]; then
    echo -e "  ${INFO} Skipping free disk space verification"
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

    stop_service dnsmasq
    if [[ "${INSTALL_WEB}" == true ]]; then
      stop_service lighttpd
    fi
    # Determine available interfaces
    get_available_interfaces
    # Find interfaces and let the user choose one
    chooseInterface
    # Decide what upstream DNS Servers to use
    setDNS
    # Let the user decide if they want to block ads over IPv4 and/or IPv6
    use4andor6
    # Let the user decide if they want the web interface to be installed automatically
    setAdminFlag
    # Let the user decide if they want query logging enabled...
    setLogging
    # Clone/Update the repos
    clone_or_update_repos

    # Install packages used by the Pi-hole
    if [[ "${INSTALL_WEB}" == true ]]; then
      # Install the Web dependencies
      DEPS=("${PIHOLE_DEPS[@]}" "${PIHOLE_WEB_DEPS[@]}")
    # Otherwise,
    else
      # just install the Core dependencies
      DEPS=("${PIHOLE_DEPS[@]}")
    fi

    install_dependent_packages DEPS[@]

    # On some systems, lighttpd is not enabled on first install. We need to enable it here if the user
    # has chosen to install the web interface, else the `LIGHTTPD_ENABLED` check will fail
    if [[ "${INSTALL_WEB}" == true ]]; then
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
    installPihole | tee -a /proc/$$/fd/3
  else
    # Source ${setupVars} to use predefined user variables in the functions
    source ${setupVars}

    # Clone/Update the repos
    clone_or_update_repos

    # Install packages used by the Pi-hole
    if [[ "${INSTALL_WEB}" == true ]]; then
      # Install the Web dependencies
      DEPS=("${PIHOLE_DEPS[@]}" "${PIHOLE_WEB_DEPS[@]}")
    # Otherwise,
    else
      # just install the Core dependencies
      DEPS=("${PIHOLE_DEPS[@]}")
    fi
    install_dependent_packages DEPS[@]

    if [[ -x "$(command -v systemctl)" ]]; then
      # Value will either be 1, if true, or 0
      LIGHTTPD_ENABLED=$(systemctl is-enabled lighttpd | grep -c 'enabled' || true)
    else
      # Value will either be 1, if true, or 0
      LIGHTTPD_ENABLED=$(service lighttpd status | awk '/Loaded:/ {print $0}' | grep -c 'enabled' || true)
    fi
    updatePihole | tee -a /proc/$$/fd/3
  fi

  # Copy the temp log file into final log location for storage
  copy_to_install_log

  if [[ "${INSTALL_WEB}" == true ]]; then
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

  echo -e "  ${INFO} Restarting services..."
  # Start services
  start_service dnsmasq
  enable_service dnsmasq

  # If the Web server was installed,
  if [[ "${INSTALL_WEB}" == true ]]; then

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
  runGravity

  # Force an update of the updatechecker
  . /opt/pihole/updatecheck.sh
  . /opt/pihole/updatecheck.sh x remote

  #
  if [[ "${useUpdateVars}" == false ]]; then
      displayFinalMessage "${pw}"
  fi

  # If the Web interface was installed,
  if [[ "${INSTALL_WEB}" == true ]]; then
    # If there is a password,
    if (( ${#pw} > 0 )) ; then
      # display the password
      echo -e "  ${INFO} Web Interface password: ${COL_LIGHT_GREEN}${pw}${COL_NC}
      This can be changed using 'pihole -a -p'\\n"
    fi
  fi

  #
  if [[ "${useUpdateVars}" == false ]]; then
    # If the Web interface was installed,
    if [[ "${INSTALL_WEB}" == true ]]; then
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
  echo -e "\\n  ${INFO} The install log is located at: ${installLogLoc}
  ${COL_LIGHT_GREEN}${INSTALL_TYPE} Complete! ${COL_NC}"

}

#
if [[ "${PH_TEST}" != true ]] ; then
  main "$@"
fi
