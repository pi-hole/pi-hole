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

webInterfaceGitUrl="https://github.com/pi-hole/AdminLTE.git"
webInterfaceDir="/var/www/html/admin"
piholeGitUrl="https://github.com/pi-hole/pi-hole.git"
piholeFilesDir="/etc/.pihole"

useUpdateVars=false

IPv4_address=""
IPv6_address=""

# Find the rows and columns will default to 80x24 is it can not be detected
screen_size=$(stty size 2>/dev/null || echo 24 80) 
rows=$(echo $screen_size | awk '{print $1}')
columns=$(echo $screen_size | awk '{print $2}')

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

	if [ -x "$(command -v sudo)" ]; then
		echo "::: Utility sudo located."
		exec curl -sSL https://install.pi-hole.net | sudo bash "$@"
		exit $?
	else
		echo "::: sudo is needed for the Web interface to run pihole commands.  Please run this script as root and it will be automatically installed."
		exit 1
	fi
fi

# Compatibility

if [ -x "$(command -v apt-get)" ]; then
	#Debian Family
	#############################################
	PKG_MANAGER="apt-get"
	PKG_CACHE="/var/lib/apt/lists/"
	UPDATE_PKG_CACHE="${PKG_MANAGER} update"
	PKG_UPDATE="${PKG_MANAGER} upgrade"
	PKG_INSTALL="${PKG_MANAGER} --yes --fix-missing install"
	# grep -c will return 1 retVal on 0 matches, block this throwing the set -e with an OR TRUE
	PKG_COUNT="${PKG_MANAGER} -s -o Debug::NoLocking=true upgrade | grep -c ^Inst || true"
	# #########################################
	# fixes for dependancy differences 
	# Debian 7 doesn't have iproute2 use iproute
	${PKG_MANAGER} install --dry-run iproute2 > /dev/null 2>&1 && IPROUTE_PKG="iproute2" || IPROUTE_PKG="iproute"
	# Ubuntu 16.04 LTS php / php5 fix
	${PKG_MANAGER} install --dry-run php5 > /dev/null 2>&1 && phpVer="php5" || phpVer="php"
	# #########################################
	INSTALLER_DEPS=( apt-utils whiptail git dhcpcd5)
	PIHOLE_DEPS=( dnsutils bc dnsmasq lighttpd ${phpVer}-common ${phpVer}-cgi curl unzip wget sudo netcat cron ${IPROUTE_PKG} )
	LIGHTTPD_USER="www-data"
	LIGHTTPD_GROUP="www-data"
	LIGHTTPD_CFG="lighttpd.conf.debian"
	DNSMASQ_USER="dnsmasq"
	package_check_install() {
		dpkg-query -W -f='${Status}' "${1}" 2>/dev/null | grep -c "ok installed" || ${PKG_INSTALL} "${1}"
	}
elif [ -x "$(command -v rpm)" ]; then
	# Fedora Family
	if [ -x "$(command -v dnf)" ]; then
		PKG_MANAGER="dnf"
	else
		PKG_MANAGER="yum"
	fi
	PKG_CACHE="/var/cache/${PKG_MANAGER}"
	UPDATE_PKG_CACHE="${PKG_MANAGER} check-update"
	PKG_UPDATE="${PKG_MANAGER} update -y"
	PKG_INSTALL="${PKG_MANAGER} install -y"
	PKG_COUNT="${PKG_MANAGER} check-update | egrep '(.i686|.x86|.noarch|.arm|.src)' | wc -l"
	INSTALLER_DEPS=( iproute net-tools procps-ng newt git )
	PIHOLE_DEPS=( epel-release bind-utils bc dnsmasq lighttpd lighttpd-fastcgi php-common php-cli php curl unzip wget findutils cronie sudo nmap-ncat )
	if grep -q 'Fedora' /etc/redhat-release; then
		remove_deps=(epel-release);
		PIHOLE_DEPS=( ${PIHOLE_DEPS[@]/$remove_deps} );
	fi
	LIGHTTPD_USER="lighttpd"
	LIGHTTPD_GROUP="lighttpd"
	LIGHTTPD_CFG="lighttpd.conf.fedora"
	DNSMASQ_USER="nobody"
	package_check_install() {
		rpm -qa | grep ^"${1}"- > /dev/null || ${PKG_INSTALL} "${1}"
	}
else
	echo "OS distribution not supported"
	exit
fi

####### FUNCTIONS ##########
spinner() {
	local pid=$1
	local delay=0.50
	local spinstr='/-\|'
	while [ "$(ps a | awk '{print $1}' | grep "${pid}")" ]; do
		local temp=${spinstr#?}
		printf " [%c]  " "${spinstr}"
		local spinstr=${temp}${spinstr%"$temp"}
		sleep ${delay}
		printf "\b\b\b\b\b\b"
	done
	printf "    \b\b\b\b"
}

find_IPv4_information() {
	# Find IP used to route to outside world
	IPv4dev=$(ip route get 8.8.8.8 | awk '{for(i=1;i<=NF;i++)if($i~/dev/)print $(i+1)}')
	IPv4_address=$(ip -o -f inet addr show dev "$IPv4dev" | awk '{print $4}' | awk 'END {print}')
	IPv4gw=$(ip route get 8.8.8.8 | awk '{print $3}')
}

get_available_interfaces() {
	# Get available interfaces. Consider only getting UP interfaces in the future, and leaving DOWN interfaces out of list.
	availableInterfaces=$(ip -o link | awk '{print $2}' | grep -v "lo" | cut -d':' -f1 | cut -d'@' -f1)
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

	while read -r line; do
		mode="OFF"
		if [[ ${firstLoop} -eq 1 ]]; then
			firstLoop=0
			mode="ON"
		fi
		interfacesArray+=("${line}" "available" "${mode}")
	done <<< "${availableInterfaces}"

	# Find out how many interfaces are available to choose from
	interfaceCount=$(echo "${availableInterfaces}" | wc -l)
	chooseInterfaceCmd=(whiptail --separate-output --radiolist "Choose An Interface (press space to select)" ${r} ${c} ${interfaceCount})
	chooseInterfaceOptions=$("${chooseInterfaceCmd[@]}" "${interfacesArray[@]}" 2>&1 >/dev/tty)
	if [[ $? = 0 ]]; then
		for desiredInterface in ${chooseInterfaceOptions}; do
			piholeInterface=${desiredInterface}
			echo "::: Using interface: $piholeInterface"
		done
	else
		echo "::: Cancel selected, exiting...."
		exit 1
	fi
}

useIPv6dialog() {
	# Show the IPv6 address used for blocking
	IPv6_address=$(ip -6 route get 2001:4860:4860::8888 | awk -F " " '{ for(i=1;i<=NF;i++) if ($i == "src") print $(i+1) }')
	whiptail --msgbox --backtitle "IPv6..." --title "IPv6 Supported" "$IPv6_address will be used to block ads." ${r} ${c}
}


use4andor6() {
	local useIPv4
	local useIPv6
	# Let use select IPv4 and/or IPv6
	cmd=(whiptail --separate-output --checklist "Select Protocols (press space to select)" ${r} ${c} 2)
	options=(IPv4 "Block ads over IPv4" on
	IPv6 "Block ads over IPv6" off)
	choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
	if [[ $? = 0 ]];then
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
			echo "::: IPv4 address: ${IPv4_address}"
			echo "::: IPv6 address: ${IPv6_address}"
		if [ ! ${useIPv4} ] && [ ! ${useIPv6} ]; then
			echo "::: Cannot continue, neither IPv4 or IPv6 selected"
			echo "::: Exiting"
			exit 1
		fi
	else
		echo "::: Cancel selected. Exiting..."
		exit 1
	fi
}

getStaticIPv4Settings() {
	# Ask if the user wants to use DHCP settings as their static IP
	if (whiptail --backtitle "Calibrating network interface" --title "Static IP Address" --yesno "Do you want to use your current network settings as a static address?
					IP address:    ${IPv4_address}
					Gateway:       ${IPv4gw}" ${r} ${c}); then
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
			IPv4_address=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 address" --inputbox "Enter your desired IPv4 address" ${r} ${c} "${IPv4_address}" 3>&1 1>&2 2>&3)
			if [[ $? = 0 ]]; then
			echo "::: Your static IPv4 address:    ${IPv4_address}"
			# Ask for the gateway
			IPv4gw=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 gateway (router)" --inputbox "Enter your desired IPv4 default gateway" ${r} ${c} "${IPv4gw}" 3>&1 1>&2 2>&3)
			if [[ $? = 0 ]]; then
				echo "::: Your static IPv4 gateway:    ${IPv4gw}"
				# Give the user a chance to review their settings before moving on
				if (whiptail --backtitle "Calibrating network interface" --title "Static IP Address" --yesno "Are these settings correct?
					IP address:    ${IPv4_address}
					Gateway:       ${IPv4gw}" ${r} ${c}); then
					# After that's done, the loop ends and we move on
					ipSettingsCorrect=True
				else
					# If the settings are wrong, the loop continues
					ipSettingsCorrect=False
				fi
			else
				# Cancelling gateway settings window
				ipSettingsCorrect=False
				echo "::: Cancel selected. Exiting..."
				exit 1
			fi
		else
			# Cancelling IPv4 settings window
			ipSettingsCorrect=False
			echo "::: Cancel selected. Exiting..."
			exit 1
		fi
		done
		# End the if statement for DHCP vs. static
	fi
}

setDHCPCD() {
	# Append these lines to dhcpcd.conf to enable a static IP
	echo "## interface ${piholeInterface}
	static ip_address=${IPv4_address}
	static routers=${IPv4gw}
	static domain_name_servers=${IPv4gw}" | tee -a /etc/dhcpcd.conf >/dev/null
}

setStaticIPv4() {
	local IFCFG_FILE
	local IPADDR
	local CIDR
	if [[ -f /etc/dhcpcd.conf ]]; then
		# Debian Family
		if grep -q "${IPv4_address}" /etc/dhcpcd.conf; then
			echo "::: Static IP already configured"
		else
			setDHCPCD
			ip addr replace dev "${piholeInterface}" "${IPv4_address}"
			echo ":::"
			echo "::: Setting IP to ${IPv4_address}.  You may need to restart after the install is complete."
			echo ":::"
		fi
	elif [[ -f /etc/sysconfig/network-scripts/ifcfg-${piholeInterface} ]];then
		# Fedora Family
		IFCFG_FILE=/etc/sysconfig/network-scripts/ifcfg-${piholeInterface}
		if grep -q "${IPv4_address}" "${IFCFG_FILE}"; then
			echo "::: Static IP already configured"
		else
			IPADDR=$(echo "${IPv4_address}" | cut -f1 -d/)
			CIDR=$(echo "${IPv4_address}" | cut -f2 -d/)
			# Backup existing interface configuration:
			cp "${IFCFG_FILE}" "${IFCFG_FILE}".pihole.orig
			# Build Interface configuration file:
			{
				echo "# Configured via Pi-Hole installer"
				echo "DEVICE=$piholeInterface"
				echo "BOOTPROTO=none"
				echo "ONBOOT=yes"
				echo "IPADDR=$IPADDR"
				echo "PREFIX=$CIDR"
				echo "GATEWAY=$IPv4gw"
				echo "DNS1=$piholeDNS1"
				echo "DNS2=$piholeDNS2"
				echo "USERCTL=no"
			}>> "${IFCFG_FILE}"
			ip addr replace dev "${piholeInterface}" "${IPv4_address}"
			if [ -x "$(command -v nmcli)" ];then
				# Tell NetworkManager to read our new sysconfig file
				nmcli con load "${IFCFG_FILE}" > /dev/null
			fi
			echo ":::"
			echo "::: Setting IP to ${IPv4_address}.  You may need to restart after the install is complete."
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
	DNSChooseCmd=(whiptail --separate-output --radiolist "Select Upstream DNS Provider. To use your own, select Custom." ${r} ${c} 6)
	DNSChooseOptions=(Google "" on
			OpenDNS "" off
			Level3 "" off
			Norton "" off
			Comodo "" off
			Custom "" off)
	DNSchoices=$("${DNSChooseCmd[@]}" "${DNSChooseOptions[@]}" 2>&1 >/dev/tty)
	if [[ $? = 0 ]];then
		case ${DNSchoices} in
			Google)
				echo "::: Using Google DNS servers."
				piholeDNS1="8.8.8.8"
				piholeDNS2="8.8.4.4"
				;;
			OpenDNS)
				echo "::: Using OpenDNS servers."
				piholeDNS1="208.67.222.222"
				piholeDNS2="208.67.220.220"
				;;
			Level3)
				echo "::: Using Level3 servers."
				piholeDNS1="4.2.2.1"
				piholeDNS2="4.2.2.2"
				;;
			Norton)
				echo "::: Using Norton ConnectSafe servers."
				piholeDNS1="199.85.126.10"
				piholeDNS2="199.85.127.10"
				;;
			Comodo)
				echo "::: Using Comodo Secure servers."
				piholeDNS1="8.26.56.26"
				piholeDNS2="8.20.247.20"
				;;
			Custom)
				until [[ ${DNSSettingsCorrect} = True ]]; do
				strInvalid="Invalid"
				if [ ! ${piholeDNS1} ]; then
					if [ ! ${piholeDNS2} ]; then
						prePopulate=""
					else
						prePopulate=", ${piholeDNS2}"
					fi
				elif  [ ${piholeDNS1} ] && [ ! ${piholeDNS2} ]; then
					prePopulate="${piholeDNS1}"
				elif [ ${piholeDNS1} ] && [ ${piholeDNS2} ]; then
					prePopulate="${piholeDNS1}, ${piholeDNS2}"
				fi

				piholeDNS=$(whiptail --backtitle "Specify Upstream DNS Provider(s)"  --inputbox "Enter your desired upstream DNS provider(s), seperated by a comma.\n\nFor example '8.8.8.8, 8.8.4.4'" ${r} ${c} "${prePopulate}" 3>&1 1>&2 2>&3)

				if [[ $? = 0 ]]; then
					piholeDNS1=$(echo "${piholeDNS}" | sed 's/[, \t]\+/,/g' | awk -F, '{print$1}')
					piholeDNS2=$(echo "${piholeDNS}" | sed 's/[, \t]\+/,/g' | awk -F, '{print$2}')
					if ! valid_ip "${piholeDNS1}" || [ ! "${piholeDNS1}" ]; then
						piholeDNS1=${strInvalid}
					fi
					if ! valid_ip "${piholeDNS2}" && [ "${piholeDNS2}" ]; then
						piholeDNS2=${strInvalid}
					fi
				else
					echo "::: Cancel selected, exiting...."
					exit 1
				fi
				if [[ ${piholeDNS1} == "${strInvalid}" ]] || [[ ${piholeDNS2} == "${strInvalid}" ]]; then
					whiptail --msgbox --backtitle "Invalid IP" --title "Invalid IP" "One or both entered IP addresses were invalid. Please try again.\n\n    DNS Server 1:   $piholeDNS1\n    DNS Server 2:   ${piholeDNS2}" ${r} ${c}
					if [[ ${piholeDNS1} == "${strInvalid}" ]]; then
						piholeDNS1=""
					fi
					if [[ ${piholeDNS2} == "${strInvalid}" ]]; then
						piholeDNS2=""
					fi
					DNSSettingsCorrect=False
				else
					if (whiptail --backtitle "Specify Upstream DNS Provider(s)" --title "Upstream DNS Provider(s)" --yesno "Are these settings correct?\n    DNS Server 1:   $piholeDNS1\n    DNS Server 2:   ${piholeDNS2}" ${r} ${c}); then
					DNSSettingsCorrect=True
				else
				# If the settings are wrong, the loop continues
					DNSSettingsCorrect=False
					fi
				fi
				done
				;;
		esac
	else
		echo "::: Cancel selected. Exiting..."
		exit 1
	fi
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
	sed -i "s/@INT@/$piholeInterface/" ${dnsmasq_pihole_01_location}
	if [[ "${piholeDNS1}" != "" ]]; then
		sed -i "s/@DNS1@/$piholeDNS1/" ${dnsmasq_pihole_01_location}
	else
		sed -i '/^server=@DNS1@/d' ${dnsmasq_pihole_01_location}
	fi
	if [[ "${piholeDNS2}" != "" ]]; then
		sed -i "s/@DNS2@/$piholeDNS2/" ${dnsmasq_pihole_01_location}
	else
		sed -i '/^server=@DNS2@/d' ${dnsmasq_pihole_01_location}
	fi

	#sed -i "s/@HOSTNAME@/$hostname/" ${dnsmasq_pihole_01_location}

	if [[ -f /etc/hostname ]]; then
		hostname=$(</etc/hostname)
	elif [ -x "$(command -v hostname)" ]; then
		hostname=$(hostname -f)
	fi

	#Replace IPv4 and IPv6 tokens in 01-pihole.conf for pi.hole resolution.
	if [[ "${IPv4_address}" != "" ]]; then
	    tmp=${IPv4_address%/*}
	    sed -i "s/@IPv4@/$tmp/" ${dnsmasq_pihole_01_location}
	else
		sed -i '/^address=\/pi.hole\/@IPv4@/d' ${dnsmasq_pihole_01_location}
		sed -i '/^address=\/@HOSTNAME@\/@IPv4@/d' ${dnsmasq_pihole_01_location}
	fi

	if [[ "${IPv6_address}" != "" ]]; then
	    sed -i "s/@IPv6@/$IPv6_address/" ${dnsmasq_pihole_01_location}
	else
		sed -i '/^address=\/pi.hole\/@IPv6@/d' ${dnsmasq_pihole_01_location}
		sed -i '/^address=\/@HOSTNAME@\/@IPv6@/d' ${dnsmasq_pihole_01_location}
	fi

	if [[ "${hostname}" != "" ]]; then
	    sed -i "s/@HOSTNAME@/$hostname/" ${dnsmasq_pihole_01_location}
	else
		sed -i '/^address=\/@HOSTNAME@*/d' ${dnsmasq_pihole_01_location}
	fi

	sed -i 's/^#conf-dir=\/etc\/dnsmasq.d$/conf-dir=\/etc\/dnsmasq.d/' ${dnsmasq_conf}
}

remove_legacy_scripts() {
	#Tidy up /usr/local/bin directory if installing over previous install.
	oldFiles=( gravity chronometer whitelist blacklist piholeLogFlush updateDashboard uninstall setupLCD piholeDebug)
	for i in "${oldFiles[@]}"; do
		if [ -f "/usr/local/bin/$i.sh" ]; then
			rm /usr/local/bin/"$i".sh
		fi
	done
}

installScripts() {
	# Install the scripts from /etc/.pihole to their various locations
	echo ":::"
	echo -n "::: Installing scripts to /opt/pihole..."
	#clear out /opt/pihole and recreate it. This allows us to remove scripts from future installs
	rm -rf /opt/pihole
	install -o "${USER}" -m755 -d /opt/pihole

	cd /etc/.pihole/

	install -o "${USER}" -Dm755 -t /opt/pihole/ gravity.sh
	install -o "${USER}" -Dm755 -t /opt/pihole/ ./advanced/Scripts/*.sh
	install -o "${USER}" -Dm755 -t /opt/pihole/ ./automated\ install/uninstall.sh
	install -o "${USER}" -Dm755 -t /usr/local/bin/ pihole

	install -Dm644 ./advanced/bash-completion/pihole /etc/bash_completion.d/pihole
	echo " done."
}

installConfigs() {
	# Install the configs from /etc/.pihole to their various locations
	echo ":::"
	echo "::: Installing configs..."
	version_check_dnsmasq
	if [ ! -d "/etc/lighttpd" ]; then
		mkdir /etc/lighttpd
		chown "${USER}":root /etc/lighttpd
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
	if [ -x "$(command -v systemctl)" ]; then
		systemctl stop "${1}" &> /dev/null & spinner $! || true
	else
		service "${1}" stop &> /dev/null & spinner $! || true
	fi
	echo " done."
}

start_service() {
	# Start/Restart service passed in as argument
	# This should not fail, it's an error if it does
	echo ":::"
	echo -n "::: Starting ${1} service..."
	if [ -x "$(command -v systemctl)" ]; then
		systemctl restart "${1}" &> /dev/null & spinner $!
	else
		service "${1}" restart &> /dev/null  & spinner $!
	fi
	echo " done."
}

enable_service() {
	# Enable service so that it will start with next reboot
	echo ":::"
	echo -n "::: Enabling ${1} service to start on reboot..."
	if [ -x "$(command -v systemctl)" ]; then
		systemctl enable "${1}" &> /dev/null & spinner $!
	else
		update-rc.d "${1}" defaults &> /dev/null  & spinner $!
	fi
	echo " done."
}

update_pacakge_cache() {
	#Running apt-get update/upgrade with minimal output can cause some issues with
	#requiring user input (e.g password for phpmyadmin see #218)

	#Check to see if apt-get update has already been run today
	#it needs to have been run at least once on new installs!
	timestamp=$(stat -c %Y ${PKG_CACHE})
	timestampAsDate=$(date -d @"${timestamp}" "+%b %e")
	today=$(date "+%b %e")

	if [ ! "${today}" == "${timestampAsDate}" ]; then
		#update package lists
		echo ":::"
		echo -n "::: ${PKG_MANAGER} update has not been run today. Running now..."
		${UPDATE_PKG_CACHE} &> /dev/null & spinner $!
		echo " done!"
	fi
}

notify_package_updates_available() {
  # Let user know if they have outdated packages on their system and
  # advise them to run a package update at soonest possible.
	echo ":::"
	echo -n "::: Checking ${PKG_MANAGER} for upgraded packages...."
	updatesToInstall=$(eval "${PKG_COUNT}")
	echo " done!"
	echo ":::"
	if [[ ${updatesToInstall} -eq "0" ]]; then
		echo "::: Your system is up to date! Continuing with Pi-hole installation..."
	else
		echo "::: There are ${updatesToInstall} updates available for your system!"
		echo "::: We recommend you run '${PKG_UPDATE}' after installing Pi-Hole! "
		echo ":::"
	fi
}

install_dependent_packages() {
	# Install packages passed in via argument array
	# No spinner - conflicts with set -e
	declare -a argArray1=("${!1}")

	for i in "${argArray1[@]}"; do
		echo -n ":::    Checking for $i..."
		package_check_install "${i}" &> /dev/null
		echo " installed!"
	done
}

getGitFiles() {
	# Setup git repos for directory and repository passed
	# as arguments 1 and 2
	echo ":::"
	echo "::: Checking for existing repository..."
	if is_repo "${1}"; then
	  update_repo "${1}"
	else
	  make_repo "${1}" "${2}"
	fi
}

is_repo() {
	# Use git to check if directory is currently under VCS
	echo -n ":::    Checking $1 is a repo..."
	cd "${1}" &> /dev/null || return 1
	git status &> /dev/null && echo " OK!"; return 0 || echo " not found!"; return 1
}

make_repo() {
	# Remove the non-repod interface and clone the interface
	echo -n ":::    Cloning $2 into $1..."
	rm -rf "${1}"
	git clone -q --depth 1 "${2}" "${1}" > /dev/null & spinner $!
	echo " done!"
}

update_repo() {
	# Pull the latest commits
	echo -n ":::     Updating repo in $1..."
	cd "${1}" || exit 1
	git stash -q > /dev/null & spinner $!
	git pull -q > /dev/null & spinner $!
	echo " done!"
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
	echo -n "::: Installing pihole custom index page..."
	if [ -d "/var/www/html/pihole" ]; then
		echo " Existing page detected, not overwriting"
	else
		mkdir /var/www/html/pihole
		if [ -f /var/www/html/index.lighttpd.html ]; then
			mv /var/www/html/index.lighttpd.html /var/www/html/index.lighttpd.orig
		else
			printf "\n:::\tNo default index.lighttpd.html file found... not backing up"
		fi
		cp /etc/.pihole/advanced/index.* /var/www/html/pihole/.
		echo " done!"
	fi
	# Install Sudoer file
	echo -n "::: Installing sudoer file..."
	mkdir -p /etc/sudoers.d/
	cp /etc/.pihole/advanced/pihole.sudo /etc/sudoers.d/pihole
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
	echo "::: Running gravity.sh"
	/opt/pihole/gravity.sh
}

create_pihole_user() {
	# Check if user pihole exists and create if not
	echo "::: Checking if user 'pihole' exists..."
	id -u pihole &> /dev/null && echo "::: User 'pihole' already exists" || (echo "::: User 'pihole' doesn't exist. Creating..." && useradd -r -s /usr/sbin/nologin pihole)
}

configureFirewall() {
	# Allow HTTP and DNS traffic
	if [ -x "$(command -v firewall-cmd)" ]; then
		firewall-cmd --state &> /dev/null && ( echo "::: Configuring firewalld for httpd and dnsmasq.." && firewall-cmd --permanent --add-port=80/tcp && firewall-cmd --permanent --add-port=53/tcp \
		&& firewall-cmd --permanent --add-port=53/udp && firewall-cmd --reload) || echo "::: FirewallD not enabled"
	elif [ -x "$(command -v iptables)" ]; then
		echo "::: Configuring iptables for httpd and dnsmasq.."
		iptables -A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
		iptables -A INPUT -p tcp -m tcp --dport 53 -j ACCEPT
		iptables -A INPUT -p udp -m udp --dport 53 -j ACCEPT
	else
		echo "::: No firewall detected.. skipping firewall configuration."
	fi
}

finalExports() {
	#If it already exists, lets overwrite it with the new values.
	if [[ -f ${setupVars} ]]; then
		rm ${setupVars}
	fi
    {
	echo "piholeInterface=${piholeInterface}"
	echo "IPv4_address=${IPv4_address}"
	echo "IPv6_address=${IPv6_address}"
	echo "piholeDNS1=${piholeDNS1}"
	echo "piholeDNS2=${piholeDNS2}"
    }>> "${setupVars}"
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
	configureSelinux
	installPiholeWeb
	installCron
	configureFirewall
	finalExports
	runGravity
}

updatePihole() {
	# Refactoring of install script has changed the name of a couple of variables. Sort them out here.
	sed -i 's/IPv4addr/IPv4_address/g' ${setupVars}
	sed -i 's/piholeIPv6/IPv6_address/g' ${setupVars}
	# Source ${setupVars} for use in the rest of the functions.
	. ${setupVars}
	# Install base files and web interface
	installScripts
	installConfigs
	CreateLogFile
	configureSelinux
	installPiholeWeb
	installCron
	configureFirewall
	runGravity
}

configureSelinux() {
	if [ -x "$(command -v getenforce)" ]; then
		printf "\n::: SELinux Detected\n"
		printf ":::\tChecking for SELinux policy development packages..."
		package_check_install "selinux-policy-devel" > /dev/null
		echo " installed!"
		printf ":::\tEnabling httpd server side includes (SSI).. "
		setsebool -P httpd_ssi_exec on &> /dev/null && echo "Success" || echo "SELinux not enabled"
		printf "\n:::\tCompiling Pi-Hole SELinux policy..\n"
		if ! [ -x "$(command -v systemctl)" ]; then
			sed -i.bak '/systemd/d' /etc/.pihole/advanced/selinux/pihole.te
		fi
		checkmodule -M -m -o /etc/pihole/pihole.mod /etc/.pihole/advanced/selinux/pihole.te
		semodule_package -o /etc/pihole/pihole.pp -m /etc/pihole/pihole.mod
		semodule -i /etc/pihole/pihole.pp
		rm -f /etc/pihole/pihole.mod
		semodule -l | grep pihole &> /dev/null && echo "::: Installed Pi-Hole SELinux policy" || echo "::: Warning: Pi-Hole SELinux policy did not install."
	fi
}

displayFinalMessage() {
	# Final completion message to user
	whiptail --msgbox --backtitle "Make it so." --title "Installation Complete!" "Configure your devices to use the Pi-hole as their DNS server using:

IPv4:	${IPv4_address%/*}
IPv6:	${IPv6_address}

If you set a new IP address, you should restart the Pi.

The install log is in /etc/pihole.
View the web interface at http://pi.hole/admin or http://${IPv4_address%/*}/admin" ${r} ${c}
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
	"${opt2a}"  "${opt2b}" 3>&2 2>&1 1>&3)

	if [[ $? = 0 ]];then
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
	else
		echo "::: Cancel selected. Exiting..."
		exit 1
	fi

}

main() {
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

	# Install packages used by the Pi-hole
	install_dependent_packages PIHOLE_DEPS[@]

	if [[ "${reconfigure}" == true ]]; then
		echo "::: --reconfigure passed to install script. Not downloading/updating local repos"
	else
		# Get Git files for Core and Admin
		getGitFiles ${piholeFilesDir} ${piholeGitUrl}
		getGitFiles ${webInterfaceDir} ${webInterfaceGitUrl}
	fi

	if [[ ${useUpdateVars} == false ]]; then
		# Display welcome dialogs
		welcomeDialogs
		# Create directory for Pi-hole storage
		mkdir -p /etc/pihole/
		# Remove legacy scripts from previous storage location
		remove_legacy_scripts
		# Stop resolver and webserver while installing proceses
		stop_service dnsmasq
		stop_service lighttpd
		# Determine available interfaces
		get_available_interfaces
		# Find interfaces and let the user choose one
		chooseInterface
		# Let the user decide if they want to block ads over IPv4 and/or IPv6
		use4andor6
		# Decide what upstream DNS Servers to use
		setDNS
		# Install and log everything to a file
		installPihole | tee ${tmpLog}
	else
		updatePihole | tee ${tmpLog}
	fi

	# Move the log file into /etc/pihole for storage
	mv ${tmpLog} ${instalLogLoc}

	if [[ "${useUpdateVars}" == false ]]; then
	    displayFinalMessage
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
		echo ":::     ${IPv4_address%/*}"
		echo ":::     ${IPv6_address}"
		echo ":::"
		echo "::: If you set a new IP address, you should restart the Pi."
	else
		echo "::: Update complete!"
	fi

	echo ":::"
	echo "::: The install log is located at: /etc/pihole/install.log"
	echo "::: View the web interface at http://pi.hole/admin or http://${IPv4_address%/*}/admin"
}

if [[ -z "$PHTEST" ]] ; then
    main "$@"
fi
