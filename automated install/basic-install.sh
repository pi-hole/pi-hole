#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Installs Pi-hole
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

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
  # fixes for dependancy differences
  # Debian 7 doesn't have iproute2 use iproute
  if ${PKG_MANAGER} install --dry-run iproute2 > /dev/null 2>&1; then
    iproute_pkg="iproute2"
  else
    iproute_pkg="iproute"
  fi
  # Prefer the php metapackage if it's there, fall back on the php5 pacakges
  if ${PKG_MANAGER} install --dry-run php > /dev/null 2>&1; then
    phpVer="php"
  else
    phpVer="php5"
  fi
  # #########################################
  INSTALLER_DEPS=(apt-utils debconf dhcpcd5 git whiptail)
  PIHOLE_DEPS=(bc cron curl dnsmasq dnsutils ${iproute_pkg} iputils-ping lighttpd lsof netcat ${phpVer}-common ${phpVer}-cgi sudo unzip wget)
  LIGHTTPD_USER="www-data"
  LIGHTTPD_GROUP="www-data"
  LIGHTTPD_CFG="lighttpd.conf.debian"
  DNSMASQ_USER="dnsmasq"

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
  INSTALLER_DEPS=(git iproute net-tools newt procps-ng)
  PIHOLE_DEPS=(bc bind-utils cronie curl dnsmasq findutils lighttpd lighttpd-fastcgi nmap-ncat php php-common php-cli sudo unzip wget)

  if ! grep -q 'Fedora' /etc/redhat-release; then
    INSTALLER_DEPS=("${INSTALLER_DEPS[@]}" "epel-release");
  fi
    LIGHTTPD_USER="lighttpd"
    LIGHTTPD_GROUP="lighttpd"
    LIGHTTPD_CFG="lighttpd.conf.fedora"
    DNSMASQ_USER="nobody"

else
  echo "OS distribution not supported"
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

  echo -n ":::    Cloning ${remoteRepo} into ${directory}..."
  # Clean out the directory if it exists for git to clone into
  if [[ -d "${directory}" ]]; then
    rm -rf "${directory}"
  fi
  git clone -q --depth 1 "${remoteRepo}" "${directory}" &> /dev/null || return $?
  echo " done!"
  return 0
}

update_repo() {
  local directory="${1}"

  # Pull the latest commits
  echo -n ":::    Updating repo in ${1}..."
  if [[ -d "${directory}" ]]; then
    cd "${directory}"
    git stash -q &> /dev/null || true # Okay for stash failure
    git pull -q &> /dev/null || return $?
    echo " done!"
  fi
  return 0
}

getGitFiles() {
  # Setup git repos for directory and repository passed
  # as arguments 1 and 2
  local directory="${1}"
  local remoteRepo="${2}"
  echo ":::"
  echo "::: Checking for existing repository..."
  if is_repo "${directory}"; then
    update_repo "${directory}" || return 1
  else
    make_repo "${directory}" "${remoteRepo}" || return 1
  fi
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
  availableInterfaces=$(ip -o link | grep -v "state DOWN\|lo" | awk '{print $2}' | cut -d':' -f1 | cut -d'@' -f1)
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
  echo "::: Verifying free disk space..."
  local required_free_kilobytes=51200
  local existing_free_kilobytes=$(df -Pk | grep -m1 '\/$' | awk '{print $4}')

  # - Unknown free disk space , not a integer
  if ! [[ "${existing_free_kilobytes}" =~ ^([0-9])+$ ]]; then
    echo "::: Unknown free disk space!"
    echo "::: We were unable to determine available free disk space on this system."
    echo "::: You may override this check and force the installation, however, it is not recommended"
    echo "::: To do so, pass the argument '--i_do_not_follow_recommendations' to the install script"
    echo "::: eg. curl -L https://install.pi-hole.net | bash /dev/stdin --i_do_not_follow_recommendations"
    exit 1
  # - Insufficient free disk space
  elif [[ ${existing_free_kilobytes} -lt ${required_free_kilobytes} ]]; then
    echo "::: Insufficient Disk Space!"
    echo "::: Your system appears to be low on disk space. pi-hole recommends a minimum of $required_free_kilobytes KiloBytes."
    echo "::: You only have ${existing_free_kilobytes} KiloBytes free."
    echo "::: If this is a new install you may need to expand your disk."
    echo "::: Try running 'sudo raspi-config', and choose the 'expand file system option'"
    echo "::: After rebooting, run this installation again. (curl -L https://install.pi-hole.net | bash)"

    echo "Insufficient free space, exiting..."
    exit 1
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
      { echo "::: Cancel selected. Exiting"; exit 1; }
      for desiredInterface in ${chooseInterfaceOptions}; do
        PIHOLE_INTERFACE=${desiredInterface}
        echo "::: Using interface: $PIHOLE_INTERFACE"
      done
  fi
}

useIPv6dialog() {
  # Show the IPv6 address used for blocking
  IPV6_ADDRESS=$(ip -6 route get 2001:4860:4860::8888 | grep -v "unreachable" | awk -F " " '{ for(i=1;i<=NF;i++) if ($i == "src") print $(i+1) }')

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
  choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty) || { echo "::: Cancel selected. Exiting"; exit 1; }
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
    echo "::: IPv4 address: ${IPV4_ADDRESS}"
    echo "::: IPv6 address: ${IPV6_ADDRESS}"
  if [ ! ${useIPv4} ] && [ ! ${useIPv6} ]; then
    echo "::: Cannot continue, neither IPv4 or IPv6 selected"
    echo "::: Exiting"
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
      { ipSettingsCorrect=False; echo "::: Cancel selected. Exiting..."; exit 1; }
      echo "::: Your static IPv4 address:    ${IPV4_ADDRESS}"

      # Ask for the gateway
      IPv4gw=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 gateway (router)" --inputbox "Enter your desired IPv4 default gateway" ${r} ${c} "${IPv4gw}" 3>&1 1>&2 2>&3) || \
      # Cancelling gateway settings window
      { ipSettingsCorrect=False; echo "::: Cancel selected. Exiting..."; exit 1; }
      echo "::: Your static IPv4 gateway:    ${IPv4gw}"

      # Give the user a chance to review their settings before moving on
      if whiptail --backtitle "Calibrating network interface" --title "Static IP Address" --yesno "Are these settings correct?
        IP address:    ${IPV4_ADDRESS}
        Gateway:       ${IPv4gw}" ${r} ${c}; then
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
  echo "## interface ${PIHOLE_INTERFACE}
  static ip_address=${IPV4_ADDRESS}
  static routers=${IPv4gw}
  static domain_name_servers=${IPv4gw}" | tee -a /etc/dhcpcd.conf >/dev/null
}

setStaticIPv4() {
  local IFCFG_FILE
  local IPADDR
  local CIDR
  if [[ -f /etc/dhcpcd.conf ]]; then
    # Debian Family
    if grep -q "${IPV4_ADDRESS}" /etc/dhcpcd.conf; then
      echo "::: Static IP already configured"
    else
      setDHCPCD
      ip addr replace dev "${PIHOLE_INTERFACE}" "${IPV4_ADDRESS}"
      echo ":::"
      echo "::: Setting IP to ${IPV4_ADDRESS}.  You may need to restart after the install is complete."
      echo ":::"
    fi
  elif [[ -f /etc/sysconfig/network-scripts/ifcfg-${PIHOLE_INTERFACE} ]];then
    # Fedora Family
    IFCFG_FILE=/etc/sysconfig/network-scripts/ifcfg-${PIHOLE_INTERFACE}
    if grep -q "${IPV4_ADDRESS}" "${IFCFG_FILE}"; then
      echo "::: Static IP already configured"
    else
      IPADDR=$(echo "${IPV4_ADDRESS}" | cut -f1 -d/)
      CIDR=$(echo "${IPV4_ADDRESS}" | cut -f2 -d/)
      # Backup existing interface configuration:
      cp "${IFCFG_FILE}" "${IFCFG_FILE}".pihole.orig
      # Build Interface configuration file:
      {
        echo "# Configured via Pi-Hole installer"
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
      echo ":::"
      echo "::: Setting IP to ${IPV4_ADDRESS}.  You may need to restart after the install is complete."
      echo ":::"
    fi
  else
    echo "::: Warning: Unable to locate configuration file to set static IPv4 address!"
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
      Custom "")
  DNSchoices=$(whiptail --separate-output --menu "Select Upstream DNS Provider. To use your own, select Custom." ${r} ${c} 6 \
    "${DNSChooseOptions[@]}" 2>&1 >/dev/tty) || \
    { echo "::: Cancel selected. Exiting"; exit 1; }
  case ${DNSchoices} in
    Google)
      echo "::: Using Google DNS servers."
      PIHOLE_DNS_1="8.8.8.8"
      PIHOLE_DNS_2="8.8.4.4"
      ;;
    OpenDNS)
      echo "::: Using OpenDNS servers."
      PIHOLE_DNS_1="208.67.222.222"
      PIHOLE_DNS_2="208.67.220.220"
      ;;
    Level3)
      echo "::: Using Level3 servers."
      PIHOLE_DNS_1="4.2.2.1"
      PIHOLE_DNS_2="4.2.2.2"
      ;;
    Norton)
      echo "::: Using Norton ConnectSafe servers."
      PIHOLE_DNS_1="199.85.126.10"
      PIHOLE_DNS_2="199.85.127.10"
      ;;
    Comodo)
      echo "::: Using Comodo Secure servers."
      PIHOLE_DNS_1="8.26.56.26"
      PIHOLE_DNS_2="8.20.247.20"
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
      { echo "::: Cancel selected. Exiting"; exit 1; }
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
  LogChoices=$("${LogToggleCommand[@]}" "${LogChooseOptions[@]}" 2>&1 >/dev/tty) || (echo "::: Cancel selected. Exiting..." && exit 1)
    case ${LogChoices} in
      "On (Recommended)")
        echo "::: Logging On."
        QUERY_LOGGING=true
        ;;
      Off)
        echo "::: Logging Off."
        QUERY_LOGGING=false
        ;;
    esac
}


version_check_dnsmasq() {
  # Check if /etc/dnsmasq.conf is from pihole.  If so replace with an original and install new in .d directory
  local dnsmasq_conf="/etc/dnsmasq.conf"
  local dnsmasq_conf_orig="/etc/dnsmasq.conf.orig"
  local dnsmasq_pihole_id_string="addn-hosts=/etc/pihole/gravity.list"
  local dnsmasq_original_config="/etc/.pihole/advanced/dnsmasq.conf.original"
  local dnsmasq_pihole_01_snippet="/etc/.pihole/advanced/01-pihole.conf"
  local dnsmasq_pihole_01_location="/etc/dnsmasq.d/01-pihole.conf"

  if [ -f ${dnsmasq_conf} ]; then
    echo -n ":::    Existing dnsmasq.conf found..."
    if grep -q ${dnsmasq_pihole_id_string} ${dnsmasq_conf}; then
      echo " it is from a previous pi-hole install."
      echo -n ":::    Backing up dnsmasq.conf to dnsmasq.conf.orig..."
      mv -f ${dnsmasq_conf} ${dnsmasq_conf_orig}
      echo " done."
      echo -n ":::    Restoring default dnsmasq.conf..."
      cp ${dnsmasq_original_config} ${dnsmasq_conf}
      echo " done."
    else
      echo " it is not a pi-hole file, leaving alone!"
    fi
  else
    echo -n ":::    No dnsmasq.conf found.. restoring default dnsmasq.conf..."
    cp ${dnsmasq_original_config} ${dnsmasq_conf}
    echo " done."
  fi

  echo -n ":::    Copying 01-pihole.conf to /etc/dnsmasq.d/01-pihole.conf..."
  cp ${dnsmasq_pihole_01_snippet} ${dnsmasq_pihole_01_location}
  echo " done."
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

  echo ":::"
  echo -n "::: Installing scripts from ${PI_HOLE_LOCAL_REPO}..."

  # Clear out script files from Pi-hole scripts directory.
  clean_existing "${PI_HOLE_INSTALL_DIR}" "${PI_HOLE_FILES[@]}"

  # Install files from local core repository
  if is_repo "${PI_HOLE_LOCAL_REPO}"; then
    cd "${PI_HOLE_LOCAL_REPO}"
    install -o "${USER}" -Dm755 -d "${PI_HOLE_INSTALL_DIR}"
    install -o "${USER}" -Dm755 -t "${PI_HOLE_INSTALL_DIR}" gravity.sh
    install -o "${USER}" -Dm755 -t "${PI_HOLE_INSTALL_DIR}" ./advanced/Scripts/*.sh
    install -o "${USER}" -Dm755 -t "${PI_HOLE_INSTALL_DIR}" ./automated\ install/uninstall.sh
    install -o "${USER}" -Dm755 -t /usr/local/bin/ pihole
    install -Dm644 ./advanced/bash-completion/pihole /etc/bash_completion.d/pihole
    echo " done."
  else
    echo " *** ERROR: Local repo ${PI_HOLE_LOCAL_REPO} not found, exiting."
    exit 1
  fi
}

installConfigs() {
  # Install the configs from /etc/.pihole to their various locations
  echo ":::"
  echo "::: Installing configs..."
  version_check_dnsmasq
  if [ ! -d "/etc/lighttpd" ]; then
    mkdir /etc/lighttpd
    chown "${USER}":root /etc/lighttpd
  elif [ -f "/etc/lighttpd/lighttpd.conf" ]; then
    mv /etc/lighttpd/lighttpd.conf /etc/lighttpd/lighttpd.conf.orig
  fi
  cp /etc/.pihole/advanced/${LIGHTTPD_CFG} /etc/lighttpd/lighttpd.conf
  mkdir -p /var/run/lighttpd
  chown ${LIGHTTPD_USER}:${LIGHTTPD_GROUP} /var/run/lighttpd
  mkdir -p /var/cache/lighttpd/compress
  chown ${LIGHTTPD_USER}:${LIGHTTPD_GROUP} /var/cache/lighttpd/compress
  mkdir -p /var/cache/lighttpd/uploads
  chown ${LIGHTTPD_USER}:${LIGHTTPD_GROUP} /var/cache/lighttpd/uploads
}

stop_service() {
  # Stop service passed in as argument.
  # Can softfail, as process may not be installed when this is called
  echo ":::"
  echo -n "::: Stopping ${1} service..."
  if command -v systemctl &> /dev/null; then
    systemctl stop "${1}" &> /dev/null || true
  else
    service "${1}" stop &> /dev/null || true
  fi
  echo " done."
}

start_service() {
  # Start/Restart service passed in as argument
  # This should not fail, it's an error if it does
  echo ":::"
  echo -n "::: Starting ${1} service..."
  if command -v systemctl &> /dev/null; then
    systemctl restart "${1}" &> /dev/null
  else
    service "${1}" restart &> /dev/null
  fi
  echo " done."
}

enable_service() {
  # Enable service so that it will start with next reboot
  echo ":::"
  echo -n "::: Enabling ${1} service to start on reboot..."
  if command -v systemctl &> /dev/null; then
    systemctl enable "${1}" &> /dev/null
  else
    update-rc.d "${1}" defaults &> /dev/null
  fi
  echo " done."
}

update_pacakge_cache() {
  #Running apt-get update/upgrade with minimal output can cause some issues with
  #requiring user input (e.g password for phpmyadmin see #218)

  #Update package cache on apt based OSes. Do this every time since
  #it's quick and packages can be updated at any time.

  echo ":::"
  echo -n "::: Updating local cache of available packages..."
  ${UPDATE_PKG_CACHE} &> /dev/null
  echo " done!"
}

notify_package_updates_available() {
  # Let user know if they have outdated packages on their system and
  # advise them to run a package update at soonest possible.
  echo ":::"
  echo -n "::: Checking ${PKG_MANAGER} for upgraded packages...."
  updatesToInstall=$(eval "${PKG_COUNT}")
  echo " done!"
  echo ":::"
  if [[ -d "/lib/modules/$(uname -r)" ]]; then
    if [[ ${updatesToInstall} -eq "0" ]]; then
      echo "::: Your system is up to date! Continuing with Pi-hole installation..."
    else
      echo "::: There are ${updatesToInstall} updates available for your system!"
      echo "::: We recommend you update your OS after installing Pi-Hole! "
      echo ":::"
    fi
  else
    echo "::: Kernel update detected, please reboot your system and try again if your installation fails."
  fi
}

install_dependent_packages() {
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
      echo -n ":::    Checking for $i..."
      if dpkg-query -W -f='${Status}' "${i}" 2>/dev/null | grep "ok installed" &> /dev/null; then
        echo " installed!"
      else
        echo " added to install list!"
        installArray+=("${i}")
      fi
    done
    if [[ ${#installArray[@]} -gt 0 ]]; then
      debconf-apt-progress -- "${PKG_INSTALL[@]}" "${installArray[@]}"
      return
    fi
      return 0
  fi

  #Fedora/CentOS
  for i in "${argArray1[@]}"; do
    echo -n ":::    Checking for $i..."
    if ${PKG_MANAGER} -q list installed "${i}" &> /dev/null; then
      echo " installed!"
    else
      echo " added to install list!"
      installArray+=("${i}")
    fi
  done
    if [[ ${#installArray[@]} -gt 0 ]]; then
      "${PKG_INSTALL[@]}" "${installArray[@]}" &> /dev/null
      return
    fi
    return 0
}

CreateLogFile() {
  # Create logfiles if necessary
  echo ":::"
  echo -n "::: Creating log file and changing owner to dnsmasq..."
  if [ ! -f /var/log/pihole.log ]; then
    touch /var/log/pihole.log
    chmod 644 /var/log/pihole.log
    chown "${DNSMASQ_USER}":root /var/log/pihole.log
    echo " done!"
  else
    echo " already exists!"
  fi
}

installPiholeWeb() {
  # Install the web interface
  echo ":::"
  echo "::: Installing pihole custom index page..."
  if [ -d "/var/www/html/pihole" ]; then
    if [ -f "/var/www/html/pihole/index.php" ]; then
      echo ":::     Existing index.php detected, not overwriting"
    else
      echo -n ":::     index.php missing, replacing... "
      cp /etc/.pihole/advanced/index.php /var/www/html/pihole/
      echo " done!"
    fi

    if [ -f "/var/www/html/pihole/index.js" ]; then
      echo ":::     Existing index.js detected, not overwriting"
    else
      echo -n ":::     index.js missing, replacing... "
      cp /etc/.pihole/advanced/index.js /var/www/html/pihole/
      echo " done!"
    fi

    if [ -f "/var/www/html/pihole/blockingpage.css" ]; then
      echo ":::     Existing blockingpage.css detected, not overwriting"
    else
      echo -n ":::     blockingpage.css missing, replacing... "
      cp /etc/.pihole/advanced/blockingpage.css /var/www/html/pihole
      echo " done!"
    fi

  else
    echo ":::     Creating directory for blocking page"
    install -d /var/www/html/pihole
    install -D /etc/.pihole/advanced/{index,blockingpage}.* /var/www/html/pihole/
    if [ -f /var/www/html/index.lighttpd.html ]; then
      mv /var/www/html/index.lighttpd.html /var/www/html/index.lighttpd.orig
    else
      printf "\n:::\tNo default index.lighttpd.html file found... not backing up"
    fi
    echo " done!"
  fi

  # Install Sudoer file
  echo ":::"
  echo -n "::: Installing sudoer file..."
  mkdir -p /etc/sudoers.d/
  cp /etc/.pihole/advanced/pihole.sudo /etc/sudoers.d/pihole
  # Add lighttpd user (OS dependent) to sudoers file
  echo "${LIGHTTPD_USER} ALL=NOPASSWD: /usr/local/bin/pihole" >> /etc/sudoers.d/pihole

  if [[ "$LIGHTTPD_USER" == "lighttpd" ]]; then
    # Allow executing pihole via sudo with Fedora
    # Usually /usr/local/bin is not permitted as directory for sudoable programms
    echo "Defaults secure_path = /sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin" >> /etc/sudoers.d/pihole
  fi

  chmod 0440 /etc/sudoers.d/pihole
  echo " done!"
}

installCron() {
  # Install the cron job
  echo ":::"
  echo -n "::: Installing latest Cron script..."
  cp /etc/.pihole/advanced/pihole.cron /etc/cron.d/pihole
  echo " done!"
}

runGravity() {
  # Run gravity.sh to build blacklists
  echo ":::"
  echo "::: Preparing to run gravity.sh to refresh hosts..."
  if ls /etc/pihole/list* 1> /dev/null 2>&1; then
    echo "::: Cleaning up previous install (preserving whitelist/blacklist)"
    rm /etc/pihole/list.*
  fi
  # Test if /etc/pihole/adlists.default exists
  if [[ ! -e /etc/pihole/adlists.default ]]; then
    cp /etc/.pihole/adlists.default /etc/pihole/adlists.default
  fi
  echo "::: Running gravity.sh"
  { /opt/pihole/gravity.sh; }
}

create_pihole_user() {
  # Check if user pihole exists and create if not
  echo "::: Checking if user 'pihole' exists..."
  if id -u pihole &> /dev/null; then
    echo "::: User 'pihole' already exists"
  else
    echo "::: User 'pihole' doesn't exist. Creating..."
    useradd -r -s /usr/sbin/nologin pihole
  fi
}

configureFirewall() {
  # Allow HTTP and DNS traffic
  if firewall-cmd --state &> /dev/null; then
    whiptail --title "Firewall in use" --yesno "We have detected a running firewall\n\nPi-hole currently requires HTTP and DNS port access.\n\n\n\nInstall Pi-hole default firewall rules?" ${r} ${c} || \
    { echo -e ":::\n::: Not installing firewall rulesets."; return 0; }
    echo -e ":::\n:::\n Configuring FirewallD for httpd and dnsmasq."
    firewall-cmd --permanent --add-port=80/tcp --add-port=53/tcp --add-port=53/udp
    firewall-cmd --reload
    return 0
  # Check for proper kernel modules to prevent failure
  elif modinfo ip_tables &> /dev/null && command -v iptables &> /dev/null; then
    # If chain Policy is not ACCEPT or last Rule is not ACCEPT
    # then check and insert our Rules above the DROP/REJECT Rule.
    if iptables -S INPUT | head -n1 | grep -qv '^-P.*ACCEPT$' || iptables -S INPUT | tail -n1 | grep -qv '^-\(A\|P\).*ACCEPT$'; then
      whiptail --title "Firewall in use" --yesno "We have detected a running firewall\n\nPi-hole currently requires HTTP and DNS port access.\n\n\n\nInstall Pi-hole default firewall rules?" ${r} ${c} || \
      { echo -e ":::\n::: Not installing firewall rulesets."; return 0; }
      echo -e ":::\n::: Installing new IPTables firewall rulesets."
      # Check chain first, otherwise a new rule will duplicate old ones
      iptables -C INPUT -p tcp -m tcp --dport 80 -j ACCEPT &> /dev/null || iptables -I INPUT 1 -p tcp -m tcp --dport 80 -j ACCEPT
      iptables -C INPUT -p tcp -m tcp --dport 53 -j ACCEPT &> /dev/null || iptables -I INPUT 1 -p tcp -m tcp --dport 53 -j ACCEPT
      iptables -C INPUT -p udp -m udp --dport 53 -j ACCEPT &> /dev/null || iptables -I INPUT 1 -p udp -m udp --dport 53 -j ACCEPT
      return 0
    fi
  else
    echo -e ":::\n::: No active firewall detected.. skipping firewall configuration."
    return 0
  fi
  echo -e ":::\n::: Skipping firewall configuration."
}

finalExports() {
  # Update variables in setupVars.conf file
  if [ -e "${setupVars}" ]; then
    sed -i.update.bak '/PIHOLE_INTERFACE/d;/IPV4_ADDRESS/d;/IPV6_ADDRESS/d;/PIHOLE_DNS_1/d;/PIHOLE_DNS_2/d;/QUERY_LOGGING/d;' "${setupVars}"
  fi
    {
  echo "PIHOLE_INTERFACE=${PIHOLE_INTERFACE}"
  echo "IPV4_ADDRESS=${IPV4_ADDRESS}"
  echo "IPV6_ADDRESS=${IPV6_ADDRESS}"
  echo "PIHOLE_DNS_1=${PIHOLE_DNS_1}"
  echo "PIHOLE_DNS_2=${PIHOLE_DNS_2}"
  echo "QUERY_LOGGING=${QUERY_LOGGING}"
    }>> "${setupVars}"

  # Look for DNS server settings which would have to be reapplied
  source "${setupVars}"
  source "/etc/.pihole/advanced/Scripts/webpage.sh"

  if [[ "${DNS_FQDN_REQUIRED}" != "" ]] ; then
    ProcessDNSSettings
  fi

  if [[ "${DHCP_ACTIVE}" != "" ]] ; then
    ProcessDHCPSettings
  fi
}

installLogrotate() {
  # Install the logrotate script
  echo ":::"
  echo -n "::: Installing latest logrotate script..."
  cp /etc/.pihole/advanced/logrotate /etc/pihole/logrotate
  # Different operating systems have different user / group
  # settings for logrotate that makes it impossible to create
  # a static logrotate file that will work with e.g.
  # Rasbian and Ubuntu at the same time. Hence, we have to
  # customize the logrotate script here in order to reflect
  # the local properties of the /var/log directory
  logusergroup="$(stat -c '%U %G' /var/log)"
  if [[ ! -z $logusergroup ]]; then
    sed -i "s/# su #/su ${logusergroup}/" /etc/pihole/logrotate
  fi
  echo " done!"
}

installPihole() {
  # Install base files and web interface
  create_pihole_user
  if [ ! -d "/var/www/html" ]; then
    mkdir -p /var/www/html
  fi
  chown ${LIGHTTPD_USER}:${LIGHTTPD_GROUP} /var/www/html
  chmod 775 /var/www/html
  usermod -a -G ${LIGHTTPD_GROUP} pihole
  if [ -x "$(command -v lighty-enable-mod)" ]; then
    lighty-enable-mod fastcgi fastcgi-php > /dev/null || true
  else
    printf "\n:::\tWarning: 'lighty-enable-mod' utility not found. Please ensure fastcgi is enabled if you experience issues.\n"
  fi
  installScripts
  installConfigs
  CreateLogFile
  installPiholeWeb
  installCron
  installLogrotate
  configureFirewall
  finalExports
  runGravity
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
  # Source ${setupVars} for use in the rest of the functions.
  source ${setupVars}
  # Install base files and web interface
  installScripts
  installConfigs
  CreateLogFile
  installPiholeWeb
  installCron
  installLogrotate
  finalExports #re-export setupVars.conf to account for any new vars added in new versions
  runGravity
}



checkSelinux() {
  if command -v getenforce &> /dev/null; then
    echo ":::"
    echo -n "::: SELinux Support Detected... Mode: "
    enforceMode=$(getenforce)
    echo "${enforceMode}"
    if [[ "${enforceMode}" == "Enforcing" ]]; then
      whiptail --title "SELinux Enforcing Detected" --yesno "SELinux is being Enforced on your system!\n\nPi-hole currently does not support SELinux, but you may still continue with the installation.\n\nNote: Admin UI Will not function fully without setting your policies correctly\n\nContinue installing Pi-hole?" ${r} ${c} || \
      { echo ":::"; echo "::: Not continuing install after SELinux Enforcing detected."; exit 1; }
      echo ":::"
      echo "::: Continuing installation with SELinux Enforcing."
      echo "::: Please refer to official SELinux documentation to create a custom policy."
    fi
  fi
}

displayFinalMessage() {
  # Final completion message to user
  whiptail --msgbox --backtitle "Make it so." --title "Installation Complete!" "Configure your devices to use the Pi-hole as their DNS server using:

IPv4:	${IPV4_ADDRESS%/*}
IPv6:	${IPV6_ADDRESS:-"Not Configured"}

If you set a new IP address, you should restart the Pi.

The install log is in /etc/pihole.
View the web interface at http://pi.hole/admin or http://${IPV4_ADDRESS%/*}/admin

Your Admin Webpage login password is ${1:-"NOT SET"}" ${r} ${c}
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
  { echo "::: Cancel selected. Exiting"; exit 1; }

  case ${UpdateCmd} in
    ${opt1a})
      echo "::: ${opt1a} option selected."
      useUpdateVars=true
      ;;
    ${opt2a})
      echo "::: ${opt2a} option selected"
      useUpdateVars=false
      ;;
    esac
}

main() {

  ######## FIRST CHECK ########
  # Must be root to install
  echo ":::"
  if [[ ${EUID} -eq 0 ]]; then
    echo "::: You are root."
  else
    echo "::: Script called with non-root privileges. The Pi-hole installs server packages and configures"
    echo "::: system networking, it requires elevated rights. Please check the contents of the script for"
    echo "::: any concerns with this requirement. Please be sure to download this script from a trusted source."
    echo ":::"
    echo "::: Detecting the presence of the sudo utility for continuation of this install..."

    if command -v sudo &> /dev/null; then
      echo "::: Utility sudo located."
      exec curl -sSL https://raw.githubusercontent.com/pi-hole/pi-hole/master/automated%20install/basic-install.sh | sudo bash "$@"
      exit $?
    else
      echo "::: sudo is needed for the Web interface to run pihole commands.  Please run this script as root and it will be automatically installed."
      exit 1
    fi
  fi

  # Check for supported distribution
  distro_check

  # Check arguments for the undocumented flags
  for var in "$@"; do
    case "$var" in
      "--reconfigure"  ) reconfigure=true;;
      "--i_do_not_follow_recommendations"   ) skipSpaceCheck=false;;
      "--unattended"     ) runUnattended=true;;
    esac
  done

  if [[ -f ${setupVars} ]]; then
    if [[ "${runUnattended}" == true ]]; then
      echo "::: --unattended passed to install script, no whiptail dialogs will be displayed"
      useUpdateVars=true
    else
      update_dialogs
    fi
  fi

  # Start the installer
  # Verify there is enough disk space for the install
  if [[ "${skipSpaceCheck}" == true ]]; then
    echo "::: --i_do_not_follow_recommendations passed to script, skipping free disk space verification!"
  else
    verifyFreeDiskSpace
  fi

  # Update package cache
  update_pacakge_cache

  # Notify user of package availability
  notify_package_updates_available

  # Install packages used by this installation script
  install_dependent_packages INSTALLER_DEPS[@]

   # Check if SELinux is Enforcing
  checkSelinux

  if [[ "${reconfigure}" == true ]]; then
    echo "::: --reconfigure passed to install script. Not downloading/updating local repos"
  else
    # Get Git files for Core and Admin
    getGitFiles ${PI_HOLE_LOCAL_REPO} ${piholeGitUrl} || \
      { echo "!!! Unable to clone ${piholeGitUrl} into ${PI_HOLE_LOCAL_REPO}, unable to continue."; \
        exit 1; \
      }
    getGitFiles ${webInterfaceDir} ${webInterfaceGitUrl} || \
      { echo "!!! Unable to clone ${webInterfaceGitUrl} into ${webInterfaceDir}, unable to continue."; \
        exit 1; \
      }
  fi

  if [[ ${useUpdateVars} == false ]]; then
    # Display welcome dialogs
    welcomeDialogs
    # Create directory for Pi-hole storage
    mkdir -p /etc/pihole/
    # Stop resolver and webserver while installing proceses
    stop_service dnsmasq
    stop_service lighttpd
    # Determine available interfaces
    get_available_interfaces
    # Find interfaces and let the user choose one
    chooseInterface
    # Decide what upstream DNS Servers to use
    setDNS
    # Let the user decide if they want to block ads over IPv4 and/or IPv6
    use4andor6
    # Let the user decide if they want query logging enabled...
    setLogging

    # Install packages used by the Pi-hole
    install_dependent_packages PIHOLE_DEPS[@]

    # Install and log everything to a file
    installPihole | tee ${tmpLog}
  else
    # update packages used by the Pi-hole
    install_dependent_packages PIHOLE_DEPS[@]

    updatePihole | tee ${tmpLog}
  fi

  # Move the log file into /etc/pihole for storage
  mv ${tmpLog} ${instalLogLoc}

  # Add password to web UI if there is none
  pw=""
  if [[ $(grep 'WEBPASSWORD' -c /etc/pihole/setupVars.conf) == 0 ]] ; then
      pw=$(tr -dc _A-Z-a-z-0-9 < /dev/urandom | head -c 8)
      /usr/local/bin/pihole -a -p "${pw}"
  fi

  if [[ "${useUpdateVars}" == false ]]; then
      displayFinalMessage "${pw}"
  fi

  echo "::: Restarting services..."
  # Start services
  start_service dnsmasq
  enable_service dnsmasq
  start_service lighttpd
  enable_service lighttpd
  echo "::: done."

  echo ":::"
  if [[ "${useUpdateVars}" == false ]]; then
    echo "::: Installation Complete! Configure your devices to use the Pi-hole as their DNS server using:"
    echo ":::     ${IPV4_ADDRESS%/*}"
    echo ":::     ${IPV6_ADDRESS}"
    echo ":::"
    echo "::: If you set a new IP address, you should restart the Pi."
    echo "::: View the web interface at http://pi.hole/admin or http://${IPV4_ADDRESS%/*}/admin"
  else
    echo "::: Update complete!"
  fi

  if (( ${#pw} > 0 )) ; then
    echo ":::"
    echo "::: Note: As security measure a password has been installed for your web interface"
    echo "::: The currently set password is"
    echo ":::                                ${pw}"
    echo ":::"
    echo "::: You can always change it using"
    echo ":::                                pihole -a -p new_password"
  fi

  echo ":::"
  echo "::: The install log is located at: /etc/pihole/install.log"
}

if [[ "${PH_TEST}" != true ]] ; then
  main "$@"
fi
