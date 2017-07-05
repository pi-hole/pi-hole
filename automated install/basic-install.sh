#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Installs Pi-hole
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.



# pi-hole.net/donate
#
# Install with this command (from your Pi):
#
# curl -L install.pi-hole.net | bash

set -e
######## VARIABLES #########
tmpLog=/tmp/pihole-install.log
instalLogLoc=/etc/pihole/install.log
setupVars=/etc/pihole/setupVars.conf
lighttpdConfig=/etc/lighttpd/lighttpd.conf
coltable=/opt/pihole/COL_TABLE

webInterfaceGitUrl="https://github.com/pi-hole/AdminLTE.git"
webInterfaceDir="/var/www/html/admin"
piholeGitUrl="https://github.com/pi-hole/pi-hole.git"
PI_HOLE_LOCAL_REPO="/etc/.pihole"
PI_HOLE_FILES=(chronometer list piholeDebug piholeLogFlush setupLCD update version gravity uninstall webpage)
PI_HOLE_INSTALL_DIR="/opt/pihole"
useUpdateVars=false

IPV4_ADDRESS=""
IPV6_ADDRESS=""
QUERY_LOGGING=true
INSTALL_WEB=true


# Find the rows and columns will default to 80x24 is it can not be detected
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
skipSpaceCheck=false
reconfigure=false
runUnattended=false

if [[ -f ${coltable} ]]; then
  source ${coltable}
else
  COL_NC='\e[0m' # No Color
  COL_LIGHT_GREEN='\e[1;32m'
  COL_LIGHT_RED='\e[1;31m'
  TICK="[${COL_LIGHT_GREEN}✓${COL_NC}]"
  CROSS="[${COL_LIGHT_RED}✗${COL_NC}]"
  INFO="[i]"
  DONE="${COL_LIGHT_GREEN} done!${COL_NC}"
  OVER="\r\033[K"
fi


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
if command -v apt-get &> /dev/null; then
  #Debian Family
  #############################################
  PKG_MANAGER="apt-get"
  UPDATE_PKG_CACHE="${PKG_MANAGER} update"
  PKG_INSTALL=(${PKG_MANAGER} --yes --no-install-recommends install)
  # grep -c will return 1 retVal on 0 matches, block this throwing the set -e with an OR TRUE
  PKG_COUNT="${PKG_MANAGER} -s -o Debug::NoLocking=true upgrade | grep -c ^Inst || true"
  # #########################################
  # fixes for dependency differences
  # Debian 7 doesn't have iproute2 use iproute
  if ${PKG_MANAGER} install --dry-run iproute2 > /dev/null 2>&1; then
    iproute_pkg="iproute2"
  else
    iproute_pkg="iproute"
  fi
  # Prefer the php metapackage if it's there, fall back on the php5 packages
  if ${PKG_MANAGER} install --dry-run php > /dev/null 2>&1; then
    phpVer="php"
  else
    phpVer="php5"
  fi
  # #########################################
  INSTALLER_DEPS=(apt-utils dialog debconf dhcpcd5 git ${iproute_pkg} whiptail)
  PIHOLE_DEPS=(bc cron curl dnsmasq dnsutils iputils-ping lsof netcat sudo unzip wget)
  PIHOLE_WEB_DEPS=(lighttpd ${phpVer}-common ${phpVer}-cgi ${phpVer}-sqlite)
  LIGHTTPD_USER="www-data"
  LIGHTTPD_GROUP="www-data"
  LIGHTTPD_CFG="lighttpd.conf.debian"
  DNSMASQ_USER="dnsmasq"

  test_dpkg_lock() {
    i=0
    while fuser /var/lib/dpkg/lock >/dev/null 2>&1 ; do
      sleep 0.5
      ((i=i+1))
    done
    # Always return success, since we only return if there is no
    # lock (anymore)
    return 0
  }

elif command -v rpm &> /dev/null; then
  # Fedora Family
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
  PIHOLE_DEPS=(bc bind-utils cronie curl dnsmasq findutils nmap-ncat sudo unzip wget)
  PIHOLE_WEB_DEPS=(lighttpd lighttpd-fastcgi php php-common php-cli)
  if ! grep -q 'Fedora' /etc/redhat-release; then
    INSTALLER_DEPS=("${INSTALLER_DEPS[@]}" "epel-release");
  fi
    LIGHTTPD_USER="lighttpd"
    LIGHTTPD_GROUP="lighttpd"
    LIGHTTPD_CFG="lighttpd.conf.fedora"
    DNSMASQ_USER="nobody"

else
  echo -e "  ${CROSS} OS distribution not supported"
  exit
fi
}

is_repo() {
  # Use git to check if directory is currently under VCS, return the value 128
  # if directory is not a repo. Return 1 if directory does not exist.
  local directory="${1}"
  local curdir
  local rc

  curdir="${PWD}"
  if [[ -d "${directory}" ]]; then
    # git -C is not used here to support git versions older than 1.8.4
    cd "${directory}"
    git status --short &> /dev/null || rc=$?
  else
    # non-zero return code if directory does not exist
    rc=1
  fi
  cd "${curdir}"
  return "${rc:-0}"
}

make_repo() {
  local directory="${1}"
  local remoteRepo="${2}"
  str="Clone ${remoteRepo} into ${directory}"
  echo -ne "  ${INFO} ${str}..."
  # Clean out the directory if it exists for git to clone into
  if [[ -d "${directory}" ]]; then
    rm -rf "${directory}"
  fi
  git clone -q --depth 1 "${remoteRepo}" "${directory}" &> /dev/null || return $?
  echo -e "${OVER}  ${TICK} ${str}"
  return 0
}

update_repo() {
  local directory="${1}"
  local curdir

  local str="Update repo in ${1}"
  curdir="${PWD}"
  cd "${directory}" &> /dev/null || return 1
  # Pull the latest commits
  echo -ne "  ${INFO} ${str}..."
  git stash --all --quiet &> /dev/null || true # Okay for stash failure
  git clean --quiet --force -d || true # Okay for already clean directory
  git pull --quiet &> /dev/null || return $?
  echo -e "${OVER}  ${TICK} ${str}"
  cd "${curdir}" &> /dev/null || return 1
  return 0
}

getGitFiles() {
  # Setup git repos for directory and repository passed
  # as arguments 1 and 2
  local directory="${1}"
  local remoteRepo="${2}"
  local str="Check for existing repository in ${1}"
  echo -ne "  ${INFO} ${str}..."
  if is_repo "${directory}"; then
    echo -e "${OVER}  ${TICK} ${str}"
    update_repo "${directory}" || { echo -e "\n  ${COL_LIGHT_RED}Error: Could not update local repository. Contact support.${COL_NC}"; exit 1; }
  else
    echo -e "${OVER}  ${CROSS} ${str}"
    make_repo "${directory}" "${remoteRepo}" || { echo -e "\n  ${COL_LIGHT_RED}Error: Could not update local repository. Contact support.${COL_NC}"; exit 1; }
  fi
  echo ""
  return 0
}

resetRepo() {
  local directory="${1}"

  cd "${directory}" &> /dev/null || return 1
  str="Resetting repository within ${1}..."
  echo -ne "  ${INFO} ${str}"
  git reset --hard &> /dev/null || return $?
  echo -e "${OVER}  ${TICK} ${str}"
  return 0
}

find_IPv4_information() {
  local route
  # Find IP used to route to outside world
  route=$(ip route get 8.8.8.8)
  IPv4dev=$(awk '{for (i=1; i<=NF; i++) if ($i~/dev/) print $(i+1)}' <<< "${route}")
  IPv4bare=$(awk '{print $7}' <<< "${route}")
  IPV4_ADDRESS=$(ip -o -f inet addr show | grep "${IPv4bare}" |  awk '{print $4}' | awk 'END {print}')
  IPv4gw=$(awk '{print $3}' <<< "${route}")

}

get_available_interfaces() {
  # Get available UP interfaces.
  availableInterfaces=$(ip --oneline link show up | grep -v "lo" | awk '{print $2}' | cut -d':' -f1 | cut -d'@' -f1)
}

welcomeDialogs() {
  # Display the welcome dialog
  whiptail --msgbox --backtitle "Welcome" --title "Pi-hole automated installer" "\n\nThis installer will transform your device into a network-wide ad blocker!" ${r} ${c}

  # Support for a part-time dev
  whiptail --msgbox --backtitle "Plea" --title "Free and open source" "\n\nThe Pi-hole is free, but powered by your donations:  http://pi-hole.net/donate" ${r} ${c}

  # Explain the need for a static address
  whiptail --msgbox --backtitle "Initiating network interface" --title "Static IP Needed" "\n\nThe Pi-hole is a SERVER so it needs a STATIC IP ADDRESS to function properly.

In the next section, you can choose to use your current network settings (DHCP) or to manually edit them." ${r} ${c}
}

verifyFreeDiskSpace() {

  # 50MB is the minimum space needed (45MB install (includes web admin bootstrap/jquery libraries etc) + 5MB one day of logs.)
  # - Fourdee: Local ensures the variable is only created, and accessible within this function/void. Generally considered a "good" coding practice for non-global variables.
  local str="Disk space check"
  local required_free_kilobytes=51200
  local existing_free_kilobytes=$(df -Pk | grep -m1 '\/$' | awk '{print $4}')

  # - Unknown free disk space , not a integer
  if ! [[ "${existing_free_kilobytes}" =~ ^([0-9])+$ ]]; then
    echo -e "  ${CROSS} ${str}
      Unknown free disk space!
      We were unable to determine available free disk space on this system.
      You may override this check, however, it is not recommended
      The option '${COL_LIGHT_RED}--i_do_not_follow_recommendations${COL_NC}' can override this
      e.g: curl -L https://install.pi-hole.net | bash /dev/stdin ${COL_LIGHT_RED}<option>${COL_NC}"
    exit 1
  # - Insufficient free disk space
  elif [[ ${existing_free_kilobytes} -lt ${required_free_kilobytes} ]]; then
    echo -e "  ${CROSS} ${str}
      Your system disk appears to only have ${existing_free_kilobytes} KB free
      It is recommended to have a minimum of ${required_free_kilobytes} KB to run the Pi-hole"
    if command -v vcgencmd &> /dev/null; then
      echo "      If this is a new install you may need to expand your disk
      Run 'sudo raspi-config', and choose the 'expand file system' option
      After rebooting, run this installation again
      e.g: curl -L https://install.pi-hole.net | bash"
    fi

    echo -e "\n      ${COL_LIGHT_RED}Insufficient free space, exiting...${COL_NC}"
    exit 1
  else
    echo -e "  ${TICK} ${str}"
  fi
}


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

  if [[ ${interfaceCount} -eq 1 ]]; then
      PIHOLE_INTERFACE="${availableInterfaces}"
  else
      while read -r line; do
        mode="OFF"
        if [[ ${firstLoop} -eq 1 ]]; then
          firstLoop=0
          mode="ON"
        fi
        interfacesArray+=("${line}" "available" "${mode}")
      done <<< "${availableInterfaces}"

      chooseInterfaceCmd=(whiptail --separate-output --radiolist "Choose An Interface (press space to select)" ${r} ${c} ${interfaceCount})
      chooseInterfaceOptions=$("${chooseInterfaceCmd[@]}" "${interfacesArray[@]}" 2>&1 >/dev/tty) || \
      { echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}"; exit 1; }
      for desiredInterface in ${chooseInterfaceOptions}; do
        PIHOLE_INTERFACE=${desiredInterface}
        echo -e "  ${INFO} Using interface: $PIHOLE_INTERFACE"
      done
  fi
}

# See https://github.com/pi-hole/pi-hole/issues/1473#issuecomment-301745953
testIPv6() {
  first="$(cut -f1 -d":" <<< "$1")"
  value1=$(((0x$first)/256))
  value2=$(((0x$first)%256))
  ((($value1&254)==252)) && echo "ULA" || true
  ((($value1&112)==32)) && echo "GUA" || true
  ((($value1==254) && (($value2&192)==128))) && echo "Link-local" || true
}

useIPv6dialog() {
  # Determine the IPv6 address used for blocking
  IPV6_ADDRESSES=($(ip -6 address | grep 'scope global' | awk '{print $2}'))

  # Determine type of found IPv6 addresses
  for i in "${IPV6_ADDRESSES[@]}"; do
    result=$(testIPv6 "$i")
    [[ "${result}" == "ULA" ]] && ULA_ADDRESS="${i%/*}"
    [[ "${result}" == "GUA" ]] && GUA_ADDRESS="${i%/*}"
  done

  # Determine which address to be used: Prefer ULA over GUA or don't use any if none found
  if [[ ! -z "${ULA_ADDRESS}" ]]; then
    IPV6_ADDRESS="${ULA_ADDRESS}"
    echo "::: Found IPv6 ULA address, using it for blocking IPv6 ads"
  elif [[ ! -z "${GUA_ADDRESS}" ]]; then
    echo "::: Found IPv6 GUA address, using it for blocking IPv6 ads"
    IPV6_ADDRESS="${GUA_ADDRESS}"
  else
    echo "::: Found neither IPv6 ULA nor GUA address, blocking IPv6 ads will not be enabled"
    IPV6_ADDRESS=""
  fi

  if [[ ! -z "${IPV6_ADDRESS}" ]]; then
    whiptail --msgbox --backtitle "IPv6..." --title "IPv6 Supported" "$IPV6_ADDRESS will be used to block ads." ${r} ${c}
  fi
}

use4andor6() {
  local useIPv4
  local useIPv6
  # Let use select IPv4 and/or IPv6
  cmd=(whiptail --separate-output --checklist "Select Protocols (press space to select)" ${r} ${c} 2)
  options=(IPv4 "Block ads over IPv4" on
  IPv6 "Block ads over IPv6" on)
  choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty) || { echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}"; exit 1; }
  for choice in ${choices}
  do
    case ${choice} in
    IPv4  )   useIPv4=true;;
    IPv6  )   useIPv6=true;;
    esac
  done
  if [[ ${useIPv4} ]]; then
    find_IPv4_information
    getStaticIPv4Settings
    setStaticIPv4
  fi
  if [[ ${useIPv6} ]]; then
    useIPv6dialog
  fi
    echo -e "  ${INFO} IPv4 address: ${IPV4_ADDRESS}"
    echo -e "  ${INFO} IPv6 address: ${IPV6_ADDRESS}"
  if [ ! ${useIPv4} ] && [ ! ${useIPv6} ]; then
    echo -e "  ${COL_LIGHT_RED}Error: Neither IPv4 or IPv6 selected${COL_NC}"
    exit 1
  fi
}

getStaticIPv4Settings() {
  local ipSettingsCorrect
  # Ask if the user wants to use DHCP settings as their static IP
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
    until [[ ${ipSettingsCorrect} = True ]]; do

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

setDHCPCD() {
  # Append these lines to dhcpcd.conf to enable a static IP
  echo "interface ${PIHOLE_INTERFACE}
  static ip_address=${IPV4_ADDRESS}
  static routers=${IPv4gw}
  static domain_name_servers=127.0.0.1" | tee -a /etc/dhcpcd.conf >/dev/null
}

setStaticIPv4() {
  local IFCFG_FILE
  local IPADDR
  local CIDR
  if [[ -f /etc/dhcpcd.conf ]]; then
    # Debian Family
    if grep -q "${IPV4_ADDRESS}" /etc/dhcpcd.conf; then
      echo -e "  ${INFO} Static IP already configured"
    else
      setDHCPCD
      ip addr replace dev "${PIHOLE_INTERFACE}" "${IPV4_ADDRESS}"
      echo -e "  ${TICK} Set IP address to ${IPV4_ADDRESS%/*}
       You may need to restart after the install is complete"
    fi
  elif [[ -f /etc/sysconfig/network-scripts/ifcfg-${PIHOLE_INTERFACE} ]];then
    # Fedora Family
    IFCFG_FILE=/etc/sysconfig/network-scripts/ifcfg-${PIHOLE_INTERFACE}
    if grep -q "${IPV4_ADDRESS}" "${IFCFG_FILE}"; then
      echo -e "  ${INFO} Static IP already configured"
    else
      IPADDR=$(echo "${IPV4_ADDRESS}" | cut -f1 -d/)
      CIDR=$(echo "${IPV4_ADDRESS}" | cut -f2 -d/)
      # Backup existing interface configuration:
      cp "${IFCFG_FILE}" "${IFCFG_FILE}".pihole.orig
      # Build Interface configuration file:
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
      ip addr replace dev "${PIHOLE_INTERFACE}" "${IPV4_ADDRESS}"
      if command -v nmcli &> /dev/null;then
        # Tell NetworkManager to read our new sysconfig file
        nmcli con load "${IFCFG_FILE}" > /dev/null
      fi
      echo -e "  ${TICK} Set IP address to ${IPV4_ADDRESS%/*}
       You may need to restart after the install is complete"
    fi
  else
    echo -e "  ${INFO} Warning: Unable to locate configuration file to set static IPv4 address"
    exit 1
  fi
}

valid_ip() {
  local ip=${1}
  local stat=1

  if [[ ${ip} =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    OIFS=$IFS
    IFS='.'
    ip=(${ip})
    IFS=${OIFS}
    [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
    && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
    stat=$?
  fi
  return ${stat}
}

setDNS() {
  local DNSSettingsCorrect

  DNSChooseOptions=(Google ""
      OpenDNS ""
      Level3 ""
      Norton ""
      Comodo ""
      DNSWatch ""
      Custom "")
  DNSchoices=$(whiptail --separate-output --menu "Select Upstream DNS Provider. To use your own, select Custom." ${r} ${c} 6 \
    "${DNSChooseOptions[@]}" 2>&1 >/dev/tty) || \
    { echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}"; exit 1; }

  echo -ne "  ${INFO} Using "
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
    Custom)
      until [[ ${DNSSettingsCorrect} = True ]]; do
      strInvalid="Invalid"
      if [ ! ${PIHOLE_DNS_1} ]; then
        if [ ! ${PIHOLE_DNS_2} ]; then
          prePopulate=""
        else
          prePopulate=", ${PIHOLE_DNS_2}"
        fi
      elif  [ ${PIHOLE_DNS_1} ] && [ ! ${PIHOLE_DNS_2} ]; then
        prePopulate="${PIHOLE_DNS_1}"
      elif [ ${PIHOLE_DNS_1} ] && [ ${PIHOLE_DNS_2} ]; then
        prePopulate="${PIHOLE_DNS_1}, ${PIHOLE_DNS_2}"
      fi

      piholeDNS=$(whiptail --backtitle "Specify Upstream DNS Provider(s)"  --inputbox "Enter your desired upstream DNS provider(s), seperated by a comma.\n\nFor example '8.8.8.8, 8.8.4.4'" ${r} ${c} "${prePopulate}" 3>&1 1>&2 2>&3) || \
      { echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}"; exit 1; }
      PIHOLE_DNS_1=$(echo "${piholeDNS}" | sed 's/[, \t]\+/,/g' | awk -F, '{print$1}')
      PIHOLE_DNS_2=$(echo "${piholeDNS}" | sed 's/[, \t]\+/,/g' | awk -F, '{print$2}')
      if ! valid_ip "${PIHOLE_DNS_1}" || [ ! "${PIHOLE_DNS_1}" ]; then
        PIHOLE_DNS_1=${strInvalid}
      fi
      if ! valid_ip "${PIHOLE_DNS_2}" && [ "${PIHOLE_DNS_2}" ]; then
        PIHOLE_DNS_2=${strInvalid}
      fi
      if [[ ${PIHOLE_DNS_1} == "${strInvalid}" ]] || [[ ${PIHOLE_DNS_2} == "${strInvalid}" ]]; then
        whiptail --msgbox --backtitle "Invalid IP" --title "Invalid IP" "One or both entered IP addresses were invalid. Please try again.\n\n    DNS Server 1:   $PIHOLE_DNS_1\n    DNS Server 2:   ${PIHOLE_DNS_2}" ${r} ${c}
        if [[ ${PIHOLE_DNS_1} == "${strInvalid}" ]]; then
          PIHOLE_DNS_1=""
        fi
        if [[ ${PIHOLE_DNS_2} == "${strInvalid}" ]]; then
          PIHOLE_DNS_2=""
        fi
        DNSSettingsCorrect=False
      else
        if (whiptail --backtitle "Specify Upstream DNS Provider(s)" --title "Upstream DNS Provider(s)" --yesno "Are these settings correct?\n    DNS Server 1:   $PIHOLE_DNS_1\n    DNS Server 2:   ${PIHOLE_DNS_2}" ${r} ${c}); then
        DNSSettingsCorrect=True
      else
      # If the settings are wrong, the loop continues
        DNSSettingsCorrect=False
        fi
      fi
      done
      ;;
  esac
}

setLogging() {
  local LogToggleCommand
  local LogChooseOptions
  local LogChoices

  LogToggleCommand=(whiptail --separate-output --radiolist "Do you want to log queries?\n (Disabling will render graphs on the Admin page useless):" ${r} ${c} 6)
  LogChooseOptions=("On (Recommended)" "" on
      Off "" off)
  LogChoices=$("${LogToggleCommand[@]}" "${LogChooseOptions[@]}" 2>&1 >/dev/tty) || (echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}" && exit 1)
    case ${LogChoices} in
      "On (Recommended)")
        echo -e "  ${INFO} Logging On."
        QUERY_LOGGING=true
        ;;
      Off)
        echo -e "  ${INFO} Logging Off."
        QUERY_LOGGING=false
        ;;
    esac
}

setAdminFlag() {
  local WebToggleCommand
  local WebChooseOptions
  local WebChoices

  WebToggleCommand=(whiptail --separate-output --radiolist "Do you wish to install the web admin interface?" ${r} ${c} 6)
  WebChooseOptions=("On (Recommended)" "" on
      Off "" off)
  WebChoices=$("${WebToggleCommand[@]}" "${WebChooseOptions[@]}" 2>&1 >/dev/tty) || (echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}" && exit 1)
    case ${WebChoices} in
      "On (Recommended)")
        echo -e "  ${INFO} Web Interface On."
        INSTALL_WEB=true
        ;;
      Off)
        echo -e "  ${INFO} Web Interface off."
        INSTALL_WEB=false
        ;;
    esac
}


version_check_dnsmasq() {
  # Check if /etc/dnsmasq.conf is from pihole.  If so replace with an original and install new in .d directory
  local dnsmasq_conf="/etc/dnsmasq.conf"
  local dnsmasq_conf_orig="/etc/dnsmasq.conf.orig"
  local dnsmasq_pihole_id_string="addn-hosts=/etc/pihole/gravity.list"
  local dnsmasq_original_config="${PI_HOLE_LOCAL_REPO}/advanced/dnsmasq.conf.original"
  local dnsmasq_pihole_01_snippet="${PI_HOLE_LOCAL_REPO}/advanced/01-pihole.conf"
  local dnsmasq_pihole_01_location="/etc/dnsmasq.d/01-pihole.conf"

  if [ -f ${dnsmasq_conf} ]; then
    echo -ne "  ${INFO} Existing dnsmasq.conf found..."
    if grep -q ${dnsmasq_pihole_id_string} ${dnsmasq_conf}; then
      echo " it is from a previous Pi-hole install."
      echo -ne "  ${INFO} Backing up dnsmasq.conf to dnsmasq.conf.orig..."
      mv -f ${dnsmasq_conf} ${dnsmasq_conf_orig}
      echo -e "${OVER}  ${TICK} Backing up dnsmasq.conf to dnsmasq.conf.orig..."
      echo -ne "  ${INFO} Restoring default dnsmasq.conf..."
      cp ${dnsmasq_original_config} ${dnsmasq_conf}
      echo -e "${OVER}  ${TICK} Restoring default dnsmasq.conf..."
    else
      echo " it is not a Pi-hole file, leaving alone!"
    fi
  else
    echo -ne "  ${INFO} No dnsmasq.conf found... restoring default dnsmasq.conf..."
    cp ${dnsmasq_original_config} ${dnsmasq_conf}
    echo -e "${OVER}  ${TICK} No dnsmasq.conf found... restoring default dnsmasq.conf..."
  fi

  echo -en "  ${INFO} Copying 01-pihole.conf to /etc/dnsmasq.d/01-pihole.conf..."
  cp ${dnsmasq_pihole_01_snippet} ${dnsmasq_pihole_01_location}
  echo -e "${OVER}  ${TICK} Copying 01-pihole.conf to /etc/dnsmasq.d/01-pihole.conf"
  sed -i "s/@INT@/$PIHOLE_INTERFACE/" ${dnsmasq_pihole_01_location}
  if [[ "${PIHOLE_DNS_1}" != "" ]]; then
    sed -i "s/@DNS1@/$PIHOLE_DNS_1/" ${dnsmasq_pihole_01_location}
  else
    sed -i '/^server=@DNS1@/d' ${dnsmasq_pihole_01_location}
  fi
  if [[ "${PIHOLE_DNS_2}" != "" ]]; then
    sed -i "s/@DNS2@/$PIHOLE_DNS_2/" ${dnsmasq_pihole_01_location}
  else
    sed -i '/^server=@DNS2@/d' ${dnsmasq_pihole_01_location}
  fi

  sed -i 's/^#conf-dir=\/etc\/dnsmasq.d$/conf-dir=\/etc\/dnsmasq.d/' ${dnsmasq_conf}

  if [[ "${QUERY_LOGGING}" == false ]] ; then
        #Disable Logging
        sed -i 's/^log-queries/#log-queries/' ${dnsmasq_pihole_01_location}
    else
        #Enable Logging
        sed -i 's/^#log-queries/log-queries/' ${dnsmasq_pihole_01_location}
    fi
}

clean_existing() {
  # Clean an exiting installation to prepare for upgrade/reinstall
  # ${1} Directory to clean; ${2} Array of files to remove
  local clean_directory="${1}"
  shift
  local old_files=( "$@" )

  for script in "${old_files[@]}"; do
    rm -f "${clean_directory}/${script}.sh"
  done
}

installScripts() {
  # Install the scripts from repository to their various locations
  local str="Installing scripts from ${PI_HOLE_LOCAL_REPO}"
  echo -ne "  ${INFO} ${str}..."

  # Clear out script files from Pi-hole scripts directory.
  clean_existing "${PI_HOLE_INSTALL_DIR}" "${PI_HOLE_FILES[@]}"

  # Install files from local core repository
  if is_repo "${PI_HOLE_LOCAL_REPO}"; then
    cd "${PI_HOLE_LOCAL_REPO}"
    install -o "${USER}" -Dm755 -d "${PI_HOLE_INSTALL_DIR}"
    install -o "${USER}" -Dm755 -t "${PI_HOLE_INSTALL_DIR}" gravity.sh
    install -o "${USER}" -Dm755 -t "${PI_HOLE_INSTALL_DIR}" ./advanced/Scripts/*.sh
    install -o "${USER}" -Dm755 -t "${PI_HOLE_INSTALL_DIR}" ./automated\ install/uninstall.sh
    install -o "${USER}" -Dm755 -t "${PI_HOLE_INSTALL_DIR}" ./advanced/Scripts/COL_TABLE
    install -o "${USER}" -Dm755 -t /usr/local/bin/ pihole
    install -Dm644 ./advanced/bash-completion/pihole /etc/bash_completion.d/pihole
    echo -e "${OVER}  ${TICK} ${str}"
  else
    echo -e "${OVER}  ${CROSS} ${str}"
    echo -e "  ${COL_LIGHT_RED}Error: Local repo ${PI_HOLE_LOCAL_REPO} not found, exiting installer${COL_NC}"
    exit 1
  fi
}

installConfigs() {
  # Install the configs from PI_HOLE_LOCAL_REPO to their various locations
  echo ""
  echo -e "  ${INFO} Installing configs from ${PI_HOLE_LOCAL_REPO}..."
  version_check_dnsmasq

  #Only mess with lighttpd configs if user has chosen to install web interface
  if [[ ${INSTALL_WEB} == true ]]; then
    if [ ! -d "/etc/lighttpd" ]; then
      mkdir /etc/lighttpd
      chown "${USER}":root /etc/lighttpd
    elif [ -f "/etc/lighttpd/lighttpd.conf" ]; then
      mv /etc/lighttpd/lighttpd.conf /etc/lighttpd/lighttpd.conf.orig
    fi
    cp ${PI_HOLE_LOCAL_REPO}/advanced/${LIGHTTPD_CFG} /etc/lighttpd/lighttpd.conf
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

start_service() {
  # Start/Restart service passed in as argument
  # This should not fail, it's an error if it does
  local str="Starting ${1} service"
  echo ""
  echo -ne "  ${INFO} ${str}..."
  if command -v systemctl &> /dev/null; then
    systemctl restart "${1}" &> /dev/null
  else
    service "${1}" restart &> /dev/null
  fi
  echo -e "${OVER}  ${TICK} ${str}"
}

enable_service() {
  # Enable service so that it will start with next reboot
  local str="Enabling ${1} service to start on reboot"
  echo ""
  echo -ne "  ${INFO} ${str}..."
  if command -v systemctl &> /dev/null; then
    systemctl enable "${1}" &> /dev/null
  else
    update-rc.d "${1}" defaults &> /dev/null
  fi
  echo -e "${OVER}  ${TICK} ${str}"
}

update_package_cache() {
  #Running apt-get update/upgrade with minimal output can cause some issues with
  #requiring user input (e.g password for phpmyadmin see #218)

  #Update package cache on apt based OSes. Do this every time since
  #it's quick and packages can be updated at any time.

  local str="Update local cache of available packages"
  echo ""
  echo -ne "  ${INFO} ${str}..."
  if eval "${UPDATE_PKG_CACHE}" &> /dev/null; then
    echo -e "${OVER}  ${TICK} ${str}"
  else
    echo -e "${OVER}  ${CROSS} ${str}"
    echo -ne "  ${COL_LIGHT_RED}Error: Unable to update package cache. Please try \"${UPDATE_PKG_CACHE}\"${COL_NC}"
    return 1
  fi
}

notify_package_updates_available() {
  # Let user know if they have outdated packages on their system and
  # advise them to run a package update at soonest possible.
  local str="Checking ${PKG_MANAGER} for upgraded packages"
  echo ""
  echo -ne "  ${INFO} ${str}..."
  updatesToInstall=$(eval "${PKG_COUNT}")
  #echo -e "\r\033[K  ${TICK} ${str}"
  #echo ""
  if [[ -d "/lib/modules/$(uname -r)" ]]; then
    if [[ ${updatesToInstall} -eq "0" ]]; then
      echo -e "${OVER}  ${TICK} ${str}... up to date!"
      echo ""
    else
      echo -e "${OVER}  ${TICK} ${str}... ${updatesToInstall} updates available"
      echo -e "  ${INFO} ${COL_LIGHT_GREEN}It is recommended to update your OS after installing the Pi-hole! ${COL_NC}"
      echo ""
    fi
  else
    echo -e "${OVER}  ${CROSS} ${str}
       Kernel update detected. If the install fails, please reboot and try again"
    echo ""
  fi
}

counter=0
install_dependent_packages() {
  counter=$((counter+1))
  if [ ${counter} == 1 ]; then
    echo -e "  ${INFO} Installer Dependency checks..."
  else
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
    for i in "${argArray1[@]}"; do
      echo -ne "  ${INFO}  Checking for $i..."
      if dpkg-query -W -f='${Status}' "${i}" 2>/dev/null | grep "ok installed" &> /dev/null; then
        echo -e "${OVER}  ${TICK} Checking for $i"
      else
        echo -e "${OVER}  ${CROSS} Checking for $i (will be installed)"
        installArray+=("${i}")
      fi
    done
    if [[ ${#installArray[@]} -gt 0 ]]; then
      test_dpkg_lock
      debconf-apt-progress -- "${PKG_INSTALL[@]}" "${installArray[@]}"
      return
    fi
      echo ""
      return 0
  fi

  #Fedora/CentOS
  for i in "${argArray1[@]}"; do
    echo -ne "  ${INFO}  Checking for $i..."
    if ${PKG_MANAGER} -q list installed "${i}" &> /dev/null; then
      echo -e "${OVER}  ${TICK} Checking for $i"
    else
      echo -e "${OVER}  ${CROSS} Checking for $i (will be installed)"
      installArray+=("${i}")
    fi
  done
    if [[ ${#installArray[@]} -gt 0 ]]; then
      "${PKG_INSTALL[@]}" "${installArray[@]}" &> /dev/null
      return
    fi
    echo ""
    return 0
}

CreateLogFile() {
  # Create logfiles if necessary
  local str="Creating log and changing owner to dnsmasq"
  echo ""
  echo -ne "  ${INFO} ${str}..."
  if [ ! -f /var/log/pihole.log ]; then
    touch /var/log/pihole.log
    chmod 644 /var/log/pihole.log
    chown "${DNSMASQ_USER}":root /var/log/pihole.log
    echo -e "${OVER}  ${TICK} ${str}"
  else
    echo -e " ${COL_LIGHT_GREEN}log already exists!${COL_NC}"
  fi
}

installPiholeWeb() {
  # Install the web interface

  echo ""
  echo "  ${INFO} Installing blocking page..."
  if [ -d "/var/www/html/pihole" ]; then

    local str="Installing index.php"
    echo -ne "  ${INFO} ${str}..."
    if [ -f "/var/www/html/pihole/index.php" ]; then
      echo -e " ${COL_LIGHT_GREEN}detected index.php, not overwriting${COL_NC}"
    else
      cp ${PI_HOLE_LOCAL_REPO}/advanced/index.php /var/www/html/pihole/
      echo -e "${OVER}  ${TICK} ${str}"
    fi

    local str="Installing index.js"
    echo -ne "  ${INFO} ${str}..."
    if [ -f "/var/www/html/pihole/index.js" ]; then
      echo -e " ${COL_LIGHT_GREEN}detected index.js, not overwriting${COL_NC}"
    else
      cp ${PI_HOLE_LOCAL_REPO}/advanced/index.js /var/www/html/pihole/
      echo -e "${OVER}  ${TICK} ${str}"
    fi

    local str="Installing blockingpage.css"
    echo -ne "  ${INFO} ${str}..."
    if [ -f "/var/www/html/pihole/blockingpage.css" ]; then
      echo -e " ${COL_LIGHT_GREEN}detected blockingpage.css, not overwriting${COL_NC}"
    else
      cp ${PI_HOLE_LOCAL_REPO}/advanced/blockingpage.css /var/www/html/pihole
      echo -e "${OVER}  ${TICK} ${str}"
    fi

  else
    local str="Creating directory for blocking page, and copying files"
    echo -ne "  ${INFO} ${str}..."
    install -d /var/www/html/pihole
    install -D ${PI_HOLE_LOCAL_REPO}/advanced/{index,blockingpage}.* /var/www/html/pihole/
    echo -e "${OVER}  ${TICK} ${str}"

    local str="Backing up index.lighttpd.html"
    echo -ne "  ${INFO} ${str}..."
    if [ -f /var/www/html/index.lighttpd.html ]; then
      mv /var/www/html/index.lighttpd.html /var/www/html/index.lighttpd.orig
      echo -e "${OVER}  ${TICK} ${str}"
    else
      echo -e "${OVER}  ${CROSS} ${str}"
      echo -e "        No default index.lighttpd.html file found... not backing up"
    fi

  fi

  # Install Sudoer file
  echo ""
  local str="Installing sudoer file"
  echo -ne "  ${INFO} ${str}..."
  mkdir -p /etc/sudoers.d/
  cp ${PI_HOLE_LOCAL_REPO}/advanced/pihole.sudo /etc/sudoers.d/pihole
  # Add lighttpd user (OS dependent) to sudoers file
  echo "${LIGHTTPD_USER} ALL=NOPASSWD: /usr/local/bin/pihole" >> /etc/sudoers.d/pihole

  if [[ "$LIGHTTPD_USER" == "lighttpd" ]]; then
    # Allow executing pihole via sudo with Fedora
    # Usually /usr/local/bin is not permitted as directory for sudoable programms
    echo "Defaults secure_path = /sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin" >> /etc/sudoers.d/pihole
  fi

  chmod 0440 /etc/sudoers.d/pihole
  echo -e "${OVER}  ${TICK} ${str}"
}

installCron() {
  # Install the cron job
  local str="Installing latest Cron script"
  echo ""
  echo -ne "  ${INFO} ${str}..."
  cp ${PI_HOLE_LOCAL_REPO}/advanced/pihole.cron /etc/cron.d/pihole
  echo -e "${OVER}  ${TICK} ${str}"
}

runGravity() {
  # Run gravity.sh to build blacklists
  echo ""
  echo -e "  ${INFO} Preparing to run gravity.sh to refresh hosts..."
  if ls /etc/pihole/list* 1> /dev/null 2>&1; then
    echo -e "  ${INFO} Cleaning up previous install (preserving whitelist/blacklist)"
    rm /etc/pihole/list.*
  fi
  # Test if /etc/pihole/adlists.default exists
  if [[ ! -e /etc/pihole/adlists.default ]]; then
    cp ${PI_HOLE_LOCAL_REPO}/adlists.default /etc/pihole/adlists.default
  fi
  echo -e "  ${INFO} Running gravity.sh"
  { /opt/pihole/gravity.sh; }
}

create_pihole_user() {
  # Check if user pihole exists and create if not
  local str="Checking for user 'pihole'"
  echo -ne "  ${INFO} ${str}..."
  if id -u pihole &> /dev/null; then
    echo -ne "${OVER}  ${TICK} ${str}"
  else
    echo -ne "${OVER}  ${CROSS} ${str}"
    local str="Creating user 'pihole'"
    echo -ne "  ${INFO} ${str}..."
    useradd -r -s /usr/sbin/nologin pihole
    echo -ne "${OVER}  ${TICK} ${str}"
  fi
}

configureFirewall() {
  # Allow HTTP and DNS traffic
  echo ""
  if firewall-cmd --state &> /dev/null; then
    whiptail --title "Firewall in use" --yesno "We have detected a running firewall\n\nPi-hole currently requires HTTP and DNS port access.\n\n\n\nInstall Pi-hole default firewall rules?" ${r} ${c} || \
    { echo -e "  ${INFO} Not installing firewall rulesets."; return 0; }
    echo -e "  ${TICK} Configuring FirewallD for httpd and dnsmasq."
    firewall-cmd --permanent --add-service=http --add-service=dns
    firewall-cmd --reload
    return 0
  # Check for proper kernel modules to prevent failure
  elif modinfo ip_tables &> /dev/null && command -v iptables &> /dev/null; then
    # If chain Policy is not ACCEPT or last Rule is not ACCEPT
    # then check and insert our Rules above the DROP/REJECT Rule.
    if iptables -S INPUT | head -n1 | grep -qv '^-P.*ACCEPT$' || iptables -S INPUT | tail -n1 | grep -qv '^-\(A\|P\).*ACCEPT$'; then
      whiptail --title "Firewall in use" --yesno "We have detected a running firewall\n\nPi-hole currently requires HTTP and DNS port access.\n\n\n\nInstall Pi-hole default firewall rules?" ${r} ${c} || \
      { echo -e "  ${INFO} Not installing firewall rulesets."; return 0; }
      echo -e "  ${TICK} Installing new IPTables firewall rulesets."
      # Check chain first, otherwise a new rule will duplicate old ones
      iptables -C INPUT -p tcp -m tcp --dport 80 -j ACCEPT &> /dev/null || iptables -I INPUT 1 -p tcp -m tcp --dport 80 -j ACCEPT
      iptables -C INPUT -p tcp -m tcp --dport 53 -j ACCEPT &> /dev/null || iptables -I INPUT 1 -p tcp -m tcp --dport 53 -j ACCEPT
      iptables -C INPUT -p udp -m udp --dport 53 -j ACCEPT &> /dev/null || iptables -I INPUT 1 -p udp -m udp --dport 53 -j ACCEPT
      iptables -C INPUT -p tcp -m tcp --dport 4711:4720 -i lo -j ACCEPT &> /dev/null || iptables -I INPUT 1 -p tcp -m tcp --dport 4711:4720 -i lo -j ACCEPT
      return 0
    fi
  else
    echo -e "  ${INFO} No active firewall detected.. skipping firewall configuration."
    return 0
  fi
  echo -e "  ${INFO} Skipping firewall configuration."
}

finalExports() {

  if [[ ${INSTALL_WEB} == false ]]; then
    #No web interface installed, and therefore no block page set IPV4/6 to 0.0.0.0 and ::/0
    if [ ${IPV4_ADDRESS} ]; then
      IPV4_ADDRESS="0.0.0.0"
    fi
    if [ ${IPV6_ADDRESS} ]; then
      IPV6_ADDRESS="::/0"
    fi
  fi

  # Update variables in setupVars.conf file
  if [ -e "${setupVars}" ]; then
    sed -i.update.bak '/PIHOLE_INTERFACE/d;/IPV4_ADDRESS/d;/IPV6_ADDRESS/d;/PIHOLE_DNS_1/d;/PIHOLE_DNS_2/d;/QUERY_LOGGING/d;/INSTALL_WEB/d;' "${setupVars}"
  fi
    {
  echo "PIHOLE_INTERFACE=${PIHOLE_INTERFACE}"
  echo "IPV4_ADDRESS=${IPV4_ADDRESS}"
  echo "IPV6_ADDRESS=${IPV6_ADDRESS}"
  echo "PIHOLE_DNS_1=${PIHOLE_DNS_1}"
  echo "PIHOLE_DNS_2=${PIHOLE_DNS_2}"
  echo "QUERY_LOGGING=${QUERY_LOGGING}"
  echo "INSTALL_WEB=${INSTALL_WEB}"
    }>> "${setupVars}"

  # Look for DNS server settings which would have to be reapplied
  source "${setupVars}"
  source "${PI_HOLE_LOCAL_REPO}/advanced/Scripts/webpage.sh"

  if [[ "${DNS_FQDN_REQUIRED}" != "" ]] ; then
    ProcessDNSSettings
  fi

  if [[ "${DHCP_ACTIVE}" != "" ]] ; then
    ProcessDHCPSettings
  fi
}

installLogrotate() {
  # Install the logrotate script
  local str="Installing latest logrotate script"
  echo ""
  echo -ne "  ${INFO} ${str}..."
  cp ${PI_HOLE_LOCAL_REPO}/advanced/logrotate /etc/pihole/logrotate
  # Different operating systems have different user / group
  # settings for logrotate that makes it impossible to create
  # a static logrotate file that will work with e.g.
  # Rasbian and Ubuntu at the same time. Hence, we have to
  # customize the logrotate script here in order to reflect
  # the local properties of the /var/log directory
  logusergroup="$(stat -c '%U %G' /var/log)"
  if [[ ! -z $logusergroup ]]; then
    sed -i "s/# su #/su ${logusergroup}/g;" /etc/pihole/logrotate
  fi
  echo -e "${OVER}  ${TICK} ${str}"
}

installPihole() {
  # Install base files and web interface
  create_pihole_user

  if [[ ${INSTALL_WEB} == true ]]; then
    if [ ! -d "/var/www/html" ]; then
      mkdir -p /var/www/html
    fi
    chown ${LIGHTTPD_USER}:${LIGHTTPD_GROUP} /var/www/html
    chmod 775 /var/www/html
    usermod -a -G ${LIGHTTPD_GROUP} pihole
    if [ -x "$(command -v lighty-enable-mod)" ]; then
      lighty-enable-mod fastcgi fastcgi-php > /dev/null || true
    else
      echo -e  "  ${INFO} Warning: 'lighty-enable-mod' utility not found
       Please ensure fastcgi is enabled if you experience issues\n"
    fi
  fi
  installScripts
  installConfigs
  CreateLogFile
  if [[ ${INSTALL_WEB} == true ]]; then
    installPiholeWeb
  fi
  installCron
  installLogrotate
  FTLdetect || echo -e "  ${CROSS} FTL Engine not installed."
  configureFirewall
  finalExports
  #runGravity
}

accountForRefactor() {
  # At some point in the future this list can be pruned, for now we'll need it to ensure updates don't break.

  # Refactoring of install script has changed the name of a couple of variables. Sort them out here.

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
  installConfigs
  CreateLogFile
  if [[ ${INSTALL_WEB} == true ]]; then
    installPiholeWeb
  fi
  installCron
  installLogrotate
  FTLdetect || echo -e "  ${CROSS} FTL Engine not installed."
  finalExports #re-export setupVars.conf to account for any new vars added in new versions
  #runGravity
}



checkSelinux() {
  if command -v getenforce &> /dev/null; then
    echo ""
    echo -ne "  ${INFO} SELinux Support Detected... Mode: "
    enforceMode=$(getenforce)
    echo "${enforceMode}"
    if [[ "${enforceMode}" == "Enforcing" ]]; then
      whiptail --title "SELinux Enforcing Detected" --yesno "SELinux is being Enforced on your system!\n\nPi-hole currently does not support SELinux, but you may still continue with the installation.\n\nNote: Admin UI Will not function fully without setting your policies correctly\n\nContinue installing Pi-hole?" ${r} ${c} || \
      { echo ""; echo -e "  ${COL_LIGHT_RED}SELinux Enforcing detected, exiting installer${COL_NC}"; exit 1; }
      echo ""
      echo -e " ${INFO} Continuing installation with SELinux Enforcing"
      echo -e " ${INFO} Please refer to official SELinux documentation to create a custom policy"
    fi
  fi
}

displayFinalMessage() {

  if [[ ${#1} -gt 0 ]] ; then
    pwstring="$1"
  elif [[ $(grep 'WEBPASSWORD' -c /etc/pihole/setupVars.conf) -gt 0 ]]; then
    pwstring="unchanged"
  else
    pwstring="NOT SET"
  fi

   if [[ ${INSTALL_WEB} == true ]]; then
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
  # reconfigure
  if [ "${reconfigure}" = true ]; then
    opt1a="Repair"
    opt1b="This will retain existing settings"
    strAdd="You will remain on the same version"
  else
    opt1a="Update"
    opt1b="This will retain existing settings."
    strAdd="You will be updated to the latest version."
  fi
  opt2a="Reconfigure"
  opt2b="This will allow you to enter new settings"

  UpdateCmd=$(whiptail --title "Existing Install Detected!" --menu "\n\nWe have detected an existing install.\n\nPlease choose from the following options: \n($strAdd)" ${r} ${c} 2 \
  "${opt1a}"  "${opt1b}" \
  "${opt2a}"  "${opt2b}" 3>&2 2>&1 1>&3) || \
  { echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}"; exit 1; }

  case ${UpdateCmd} in
    ${opt1a})
      echo -e "  ${INFO} ${opt1a} option selected."
      useUpdateVars=true
      ;;
    ${opt2a})
      echo -e "  ${INFO} ${opt2a} option selected"
      useUpdateVars=false
      ;;
    esac
}

clone_or_update_repos() {
  if [[ "${reconfigure}" == true ]]; then
    echo "  ${INFO} Performing reconfiguration, skipping download of local repos"
    resetRepo ${PI_HOLE_LOCAL_REPO} || \
      { echo -e "  ${COL_LIGHT_RED}Unable to reset ${PI_HOLE_LOCAL_REPO}, exiting installer${COL_NC}"; \
        exit 1; \
      }
    if [[ ${INSTALL_WEB} == true ]]; then
      resetRepo ${webInterfaceDir} || \
        { echo -e "  ${COL_LIGHT_RED}Unable to reset ${webInterfaceDir}, exiting installer${COL_NC}"; \
          exit 1; \
        }
    fi
  else
    # Get Git files for Core and Admin
    getGitFiles ${PI_HOLE_LOCAL_REPO} ${piholeGitUrl} || \
      { echo "!!! Unable to clone ${piholeGitUrl} into ${PI_HOLE_LOCAL_REPO}, unable to continue."; \
        exit 1; \
      }

      if [[ ${INSTALL_WEB} == true ]]; then
        getGitFiles ${webInterfaceDir} ${webInterfaceGitUrl} || \
        { echo -e "  ${COL_LIGHT_RED}Unable to clone ${webInterfaceGitUrl} into ${webInterfaceDir}, exiting installer${COL_NC}"; \
          exit 1; \
        }
      fi
  fi
}

FTLinstall() {
  # Download and install FTL binary
  local binary="${1}"
  local latesttag
  local orig_dir
  local str="Installing FTL"
  echo -ne "  ${INFO} ${str}..."

  orig_dir="${PWD}"
  latesttag=$(curl -sI https://github.com/pi-hole/FTL/releases/latest | grep "Location" | awk -F '/' '{print $NF}')
  # Tags should always start with v, check for that.
  if [[ ! "${latesttag}" == v* ]]; then
    echo -e "${OVER}  ${CROSS} ${str}"
    echo -e "  ${COL_LIGHT_RED}Error: Unable to get latest release location from GitHub${COL_NC}"
    return 1
  fi
  if curl -sSL --fail "https://github.com/pi-hole/FTL/releases/download/${latesttag%$'\r'}/${binary}" -o "/tmp/${binary}"; then
    # Get sha1 of the binary we just downloaded for verification.
    curl -sSL --fail "https://github.com/pi-hole/FTL/releases/download/${latesttag%$'\r'}/${binary}.sha1" -o "/tmp/${binary}.sha1"
    # Check if we just downloaded text, or a binary file.
    cd /tmp
    if sha1sum --status --quiet -c "${binary}".sha1; then
      echo -n "transferred... "
      stop_service pihole-FTL &> /dev/null
      install -T -m 0755 /tmp/${binary} /usr/bin/pihole-FTL
      rm /tmp/${binary} /tmp/${binary}.sha1
      cd "${orig_dir}"
      install -T -m 0755 "${PI_HOLE_LOCAL_REPO}/advanced/pihole-FTL.service" "/etc/init.d/pihole-FTL"
      echo -e "${OVER}  ${TICK} ${str}"
      return 0
    else
      echo -e "${OVER}  ${CROSS} ${str}"
      echo -e "  ${COL_LIGHT_RED}Error: Download of binary from Github failed${COL_NC}"
      cd "${orig_dir}"
      return 1
    fi
  else
    cd "${orig_dir}"
    echo -e "${OVER}  ${CROSS} ${str}"
    echo -e "  ${COL_LIGHT_RED}Error: URL not found${COL_NC}"
  fi
}

FTLdetect() {
  # Detect suitable FTL binary platform
  echo ""
  echo -e "  ${INFO} Downloading latest version of FTL..."

  local machine
  local binary

  machine=$(uname -m)

  local str="Detecting architecture"
  echo -ne "  ${INFO} ${str}..."
  if [[ ${machine} == arm* || ${machine} == *aarch* ]]; then
    # ARM
    local rev=$(uname -m | sed "s/[^0-9]//g;")
    local lib=$(ldd /bin/ls | grep -E '^\s*/lib' | awk '{ print $1 }')
    if [[ "$lib" == "/lib/ld-linux-aarch64.so.1" ]]; then
      echo -e "${OVER}  ${TICK} Detected ARM-aarch64 architecture"
      binary="pihole-FTL-aarch64-linux-gnu"
    elif [[ "$lib" == "/lib/ld-linux-armhf.so.3" ]]; then
      if [ "$rev" -gt "6" ]; then
        echo -e "${OVER}  ${TICK} Detected ARM-hf architecture (armv7+)"
        binary="pihole-FTL-arm-linux-gnueabihf"
      else
        echo -e "${OVER}  ${TICK} Detected ARM-hf architecture (armv6 or lower) Using ARM binary"
        binary="pihole-FTL-arm-linux-gnueabi"
      fi
    else
      echo -e "${OVER}  ${TICK} Detected ARM architecture"
      binary="pihole-FTL-arm-linux-gnueabi"
    fi
  elif [[ $machine == ppc ]]; then
    # PowerPC
    echo ":::  Detected PowerPC architecture"
    binary="pihole-FTL-powerpc-linux-gnu"
  elif [[ ${machine} == x86_64 ]]; then
    # 64bit
    echo -e "${OVER}  ${TICK} Detected x86_64 architecture"
    binary="pihole-FTL-linux-x86_64"
  else
    # Something else - we try to use 32bit executable and warn the user
    if [[ ! ${machine} == i686 ]]; then
      echo -e "${OVER}  ${CROSS} ${str}...
      ${COL_LIGHT_RED}Not able to detect architecture (unknown: ${machine}), trying 32bit executable
      Contact support if you experience issues (e.g: FTL not running)${COL_NC}"
    else
      echo -e "${OVER}  ${TICK} Detected 32bit (i686) architecture"
    fi
    binary="pihole-FTL-linux-x86_32"
  fi

  FTLinstall "${binary}" || return 1

}

main() {

  ######## FIRST CHECK ########
  # Must be root to install
  show_ascii_berry
  local str="Root user check"
  echo ""

  if [[ ${EUID} -eq 0 ]]; then
    echo -e "  ${TICK} ${str}"
  else
    echo -e "  ${CROSS} ${str}
       Script called with non-root privileges
       The Pi-hole requires elevated privleges to install and run
       Please check the installer for any concerns regarding this requirement
       Make sure to download this script from a trusted source"
    echo ""
    echo -ne "  ${INFO} Sudo utility check"

    if command -v sudo &> /dev/null; then
      echo -e "${OVER}  ${TICK} Sudo utility check"
      exec curl -sSL https://raw.githubusercontent.com/pi-hole/pi-hole/master/automated%20install/basic-install.sh | sudo bash "$@"
      exit $?
    else
      echo -e "${OVER}  ${CROSS} Sudo utility check
       Sudo is needed for the Web Interface to run pihole commands\n
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
      "--i_do_not_follow_recommendations" ) skipSpaceCheck=false;;
      "--unattended" ) runUnattended=true;;
    esac
  done

  if [[ -f ${setupVars} ]]; then
    if [[ "${runUnattended}" == true ]]; then
      echo -e "  ${INFO} Performing unattended setup, no whiptail dialogs will be displayed"
      useUpdateVars=true
    else
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


  if [[ ${useUpdateVars} == false ]]; then
    # Display welcome dialogs
    welcomeDialogs
    # Create directory for Pi-hole storage
    mkdir -p /etc/pihole/

    stop_service dnsmasq
    if [[ ${INSTALL_WEB} == true ]]; then
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
    if [[ ${INSTALL_WEB} == true ]]; then
      DEPS=("${PIHOLE_DEPS[@]}" "${PIHOLE_WEB_DEPS[@]}")
    else
      DEPS=("${PIHOLE_DEPS[@]}")
    fi
    install_dependent_packages DEPS[@]


    # Install and log everything to a file
    installPihole | tee ${tmpLog}
  else
    # Clone/Update the repos
    clone_or_update_repos

    # Source ${setupVars} for use in the rest of the functions.
    source ${setupVars}

    # Install packages used by the Pi-hole
    if [[ ${INSTALL_WEB} == true ]]; then
      DEPS=("${PIHOLE_DEPS[@]}" "${PIHOLE_WEB_DEPS[@]}")
    else
      DEPS=("${PIHOLE_DEPS[@]}")
    fi
    install_dependent_packages DEPS[@]

    updatePihole | tee ${tmpLog}
  fi

  # Move the log file into /etc/pihole for storage
  mv ${tmpLog} ${instalLogLoc}

  if [[ ${INSTALL_WEB} == true ]]; then
    # Add password to web UI if there is none
    pw=""
    if [[ $(grep 'WEBPASSWORD' -c /etc/pihole/setupVars.conf) == 0 ]] ; then
        pw=$(tr -dc _A-Z-a-z-0-9 < /dev/urandom | head -c 8)
        . /opt/pihole/webpage.sh
        echo "WEBPASSWORD=$(HashPassword ${pw})" >> ${setupVars}
    fi
  fi

  echo -e "  ${INFO} Restarting services..."
  # Start services
  start_service dnsmasq
  enable_service dnsmasq

  if [[ ${INSTALL_WEB} == true ]]; then
    start_service lighttpd
    enable_service lighttpd
  fi

  runGravity

  start_service pihole-FTL
  enable_service pihole-FTL

  if [[ "${useUpdateVars}" == false ]]; then
      displayFinalMessage "${pw}"
  fi

  if [[ ${INSTALL_WEB} == true ]]; then
    if (( ${#pw} > 0 )) ; then
      echo -e "  ${INFO} Web Interface password: ${COL_LIGHT_GREEN}${pw}${COL_NC}
       This can be changed using 'pihole -a -p'"
      echo ""
    fi
  fi

  if [[ "${useUpdateVars}" == false ]]; then
    if [[ ${INSTALL_WEB} == true ]]; then
      echo -e "  View the web interface at http://pi.hole/admin or http://${IPV4_ADDRESS%/*}/admin"
      echo ""
    fi
    echo "  You may now configure your devices to use the Pi-hole as their DNS server"
    [[ -n "${IPV4_ADDRESS%/*}" ]] && echo -e "  ${INFO} Pi-hole DNS (IPv4): ${IPV4_ADDRESS%/*}"
    [[ -n "${IPV6_ADDRESS}" ]] && echo -e "  ${INFO} Pi-hole DNS (IPv6): ${IPV6_ADDRESS}"
    echo -e "  If you set a new IP address, please restart the server running the Pi-hole"
    INSTALL_TYPE="Installation"
  else
    INSTALL_TYPE="Update"
  fi

  echo -e "\n  ${INFO} The install log is located at: /etc/pihole/install.log
  ${COL_LIGHT_GREEN}${INSTALL_TYPE} Complete! ${COL_NC}"
}

if [[ "${PH_TEST}" != true ]] ; then
  main "$@"
fi
