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


######## VARIABLES #########


tmpLog=/tmp/pihole-install.log
instalLogLoc=/etc/pihole/install.log
setupVars=/etc/pihole/setupVars.conf

webInterfaceGitUrl="https://github.com/pi-hole/AdminLTE.git"
webInterfaceDir="/var/www/html/admin"
piholeGitUrl="https://github.com/pi-hole/pi-hole.git"
piholeFilesDir="/etc/.pihole"

useUpdateVars=false

# Find the rows and columns
rows=$(tput lines)
columns=$(tput cols)

# Divide by two so the dialogs take up half of the screen, which looks nice.
r=$(( rows / 2 ))
c=$(( columns / 2 ))

######## FIRST CHECK ########
# Must be root to install
echo ":::"
if [[ $EUID -eq 0 ]];then
	echo "::: You are root."
else
	echo "::: sudo will be used for the install."
	# Check if it is actually installed
	# If it isn't, exit because the install cannot complete
	if [ -x "$(command -v sudo)" ];then
		export SUDO="sudo"
	else
		echo "::: sudo is needed for the Web interface to run pihole commands.  Please run this script as root and it will be automatically installed."
		exit 1
	fi
fi

# Compatibility

if [ -x "$(command -v apt-get)" ];then
	#Debian Family
	#Decide if php should be `php5` or just `php` (Fixes issues with Ubuntu 16.04 LTS)
	phpVer="php"
	${SUDO} apt-get install --dry-run php5 > /dev/null 2>&1
	if [ $? == 0 ]; then
	    phpVer="php5"
	fi
	#############################################
	PKG_MANAGER="apt-get"
	PKG_CACHE="/var/cache/apt"
	UPDATE_PKG_CACHE="$PKG_MANAGER -qq update"
	PKG_UPDATE="$PKG_MANAGER upgrade"
	PKG_INSTALL="$PKG_MANAGER --yes --quiet install"
	PKG_COUNT="$PKG_MANAGER -s -o Debug::NoLocking=true upgrade | grep -c ^Inst"
	INSTALLER_DEPS=( apt-utils whiptail dhcpcd5)
	PIHOLE_DEPS=( dnsutils bc dnsmasq lighttpd ${phpVer}-common ${phpVer}-cgi ${phpVer} git curl unzip wget sudo netcat cron iproute2 )
	LIGHTTPD_USER="www-data"
	LIGHTTPD_GROUP="www-data"
	LIGHTTPD_CFG="lighttpd.conf.debian"
	package_check() {
		dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -c "ok installed"
	}
elif [ -x "$(command -v rpm)" ];then
	# Fedora Family
	if [ -x "$(command -v dnf)" ];then
		PKG_MANAGER="dnf"
	else
		PKG_MANAGER="yum"
	fi
	PKG_CACHE="/var/cache/$PKG_MANAGER"
	UPDATE_PKG_CACHE="$PKG_MANAGER check-update -q"
	PKG_UPDATE="$PKG_MANAGER update -y"
	PKG_INSTALL="$PKG_MANAGER install -y"
	PKG_COUNT="$PKG_MANAGER check-update | grep -v ^Last | grep -c ^[a-zA-Z0-9]"
	INSTALLER_DEPS=( iproute net-tools procps-ng newt )
	PIHOLE_DEPS=( epel-release bind-utils bc dnsmasq lighttpd lighttpd-fastcgi php-common php-cli php git curl unzip wget findutils cronie sudo nmap-ncat )
	LIGHTTPD_USER="lighttpd"
	LIGHTTPD_GROUP="lighttpd"
	LIGHTTPD_CFG="lighttpd.conf.fedora"
	package_check() {
		rpm -qa | grep ^$1- > /dev/null
	}
else
	echo "OS distribution not supported"
	exit
fi

####### FUNCTIONS ##########
spinner()
{
	local pid=$1
    local delay=0.50
    local spinstr='/-\|'
    while [ "$(ps a | awk '{print $1}' | grep "$pid")" ]; do
		local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=${temp}${spinstr%"$temp"}
        sleep ${delay}
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

findIPRoute() {
	# Find IP used to route to outside world
	IPv4dev=$(ip route get 8.8.8.8 | awk '{for(i=1;i<=NF;i++)if($i~/dev/)print $(i+1)}')
	IPv4addr=$(ip -o -f inet addr show dev "$IPv4dev" | awk '{print $4}' | awk 'END {print}')
	IPv4gw=$(ip route get 8.8.8.8 | awk '{print $3}')
	availableInterfaces=$(ip -o link | awk '{print $2}' | grep -v "lo" | cut -d':' -f1 | cut -d'@' -f1)
}


welcomeDialogs() {
	# Display the welcome dialog
	whiptail --msgbox --backtitle "Welcome" --title "Pi-hole automated installer" "This installer will transform your Raspberry Pi into a network-wide ad blocker!" ${r} ${c}

	# Support for a part-time dev
	whiptail --msgbox --backtitle "Plea" --title "Free and open source" "The Pi-hole is free, but powered by your donations:  http://pi-hole.net/donate" ${r} ${c}

	# Explain the need for a static address
	whiptail --msgbox --backtitle "Initiating network interface" --title "Static IP Needed" "The Pi-hole is a SERVER so it needs a STATIC IP ADDRESS to function properly.

In the next section, you can choose to use your current network settings (DHCP) or to manually edit them." ${r} ${c}
}


verifyFreeDiskSpace() {

	# 50MB is the minimum space needed (45MB install (includes web admin bootstrap/jquery libraries etc) + 5MB one day of logs.)
	# - Fourdee: Local ensures the variable is only created, and accessible within this function/void. Generally considered a "good" coding practice for non-global variables.
	echo "::: Verifying free disk space..."
	local required_free_kilobytes=51200
	local existing_free_kilobytes=$(df -Pk | grep -m1 '\/$' | awk '{print $4}')

	# - Unknown free disk space , not a integer
	if ! [[ "$existing_free_kilobytes" =~ ^([0-9])+$ ]]; then
        echo "::: Unknown free disk space!"
        echo "::: We were unable to determine available free disk space on this system."
        echo "::: You may override this check and force the installation, however, it is not recommended"
        echo "::: To do so, pass the argument '--force' to the install script"
        echo "::: eg. curl -L https://install.pi-hole.net | bash /dev/stdin --force"
        exit 1
	# - Insufficient free disk space
	elif [[ ${existing_free_kilobytes} -lt ${required_free_kilobytes} ]]; then
	    echo "::: Insufficient Disk Space!"
	    echo "::: Your system appears to be low on disk space. pi-hole recommends a minimum of $required_free_kilobytes KiloBytes."
	    echo "::: You only have $existing_free_kilobytes KiloBytes free."
	    echo "::: If this is a new install you may need to expand your disk."
	    echo "::: Try running 'sudo raspi-config', and choose the 'expand file system option'"
	    echo "::: After rebooting, run this installation again. (curl -L https://install.pi-hole.net | bash)"

		echo "Insufficient free space, exiting..."
		exit 1

	fi

}


chooseInterface() {
	# Turn the available interfaces into an array so it can be used with a whiptail dialog
	interfacesArray=()
	firstLoop=1

	while read -r line
	do
		mode="OFF"
		if [[ ${firstLoop} -eq 1 ]]; then
			firstLoop=0
			mode="ON"
		fi
		interfacesArray+=("$line" "available" "$mode")
	done <<< "$availableInterfaces"

	# Find out how many interfaces are available to choose from
	interfaceCount=$(echo "$availableInterfaces" | wc -l)
	chooseInterfaceCmd=(whiptail --separate-output --radiolist "Choose An Interface (press space to select)" ${r} ${c} ${interfaceCount})
	chooseInterfaceOptions=$("${chooseInterfaceCmd[@]}" "${interfacesArray[@]}" 2>&1 >/dev/tty)
	if [[ $? = 0 ]]; then
		for desiredInterface in ${chooseInterfaceOptions}
		do
			piholeInterface=${desiredInterface}
			echo "::: Using interface: $piholeInterface"
		done
	else
		echo "::: Cancel selected, exiting...."
		exit 1
	fi

}

use4andor6() {
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

		if [ ${useIPv4} ] && [ ! ${useIPv6} ]; then
			getStaticIPv4Settings
			setStaticIPv4
			echo "::: Using IPv4 on $IPv4addr"
			echo "::: IPv6 will NOT be used."
		fi
		if [ ! ${useIPv4} ] && [ ${useIPv6} ]; then
			useIPv6dialog
			echo "::: IPv4 will NOT be used."
			echo "::: Using IPv6 on $piholeIPv6"
		fi
		if [ ${useIPv4} ] && [  ${useIPv6} ]; then
			getStaticIPv4Settings
			setStaticIPv4
			useIPv6dialog
			echo "::: Using IPv4 on $IPv4addr"
			echo "::: Using IPv6 on $piholeIPv6"
		fi
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

useIPv6dialog() {
	# Show the IPv6 address used for blocking
	piholeIPv6=$(ip -6 route get 2001:4860:4860::8888 | awk -F " " '{ for(i=1;i<=NF;i++) if ($i == "src") print $(i+1) }')
	whiptail --msgbox --backtitle "IPv6..." --title "IPv6 Supported" "$piholeIPv6 will be used to block ads." ${r} ${c}
}

getStaticIPv4Settings() {
	# Ask if the user wants to use DHCP settings as their static IP
	if (whiptail --backtitle "Calibrating network interface" --title "Static IP Address" --yesno "Do you want to use your current network settings as a static address?
					IP address:    $IPv4addr
					Gateway:       $IPv4gw" ${r} ${c}); then
		# If they choose yes, let the user know that the IP address will not be available via DHCP and may cause a conflict.
		whiptail --msgbox --backtitle "IP information" --title "FYI: IP Conflict" "It is possible your router could still try to assign this IP to a device, which would cause a conflict.  But in most cases the router is smart enough to not do that.
If you are worried, either manually set the address, or modify the DHCP reservation pool so it does not include the IP you want.
It is also possible to use a DHCP reservation, but if you are going to do that, you might as well set a static address." ${r} ${c}
		# Nothing else to do since the variables are already set above
	else
		# Otherwise, we need to ask the user to input their desired settings.
		# Start by getting the IPv4 address (pre-filling it with info gathered from DHCP)
		# Start a loop to let the user enter their information with the chance to go back and edit it if necessary
		until [[ ${ipSettingsCorrect} = True ]]
		do
			# Ask for the IPv4 address
			IPv4addr=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 address" --inputbox "Enter your desired IPv4 address" ${r} ${c} "$IPv4addr" 3>&1 1>&2 2>&3)
			if [[ $? = 0 ]];then
			echo "::: Your static IPv4 address:    $IPv4addr"
			# Ask for the gateway
			IPv4gw=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 gateway (router)" --inputbox "Enter your desired IPv4 default gateway" ${r} ${c} "$IPv4gw" 3>&1 1>&2 2>&3)
			if [[ $? = 0 ]];then
				echo "::: Your static IPv4 gateway:    $IPv4gw"
				# Give the user a chance to review their settings before moving on
				if (whiptail --backtitle "Calibrating network interface" --title "Static IP Address" --yesno "Are these settings correct?
					IP address:    $IPv4addr
					Gateway:       $IPv4gw" ${r} ${c}); then
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
	echo "## interface $piholeInterface
	static ip_address=$IPv4addr
	static routers=$IPv4gw
	static domain_name_servers=$IPv4gw" | ${SUDO} tee -a /etc/dhcpcd.conf >/dev/null
}

setStaticIPv4() {
	if [[ -f /etc/dhcpcd.conf ]];then
		# Debian Family
		if grep -q "$IPv4addr" /etc/dhcpcd.conf; then
			echo "::: Static IP already configured"
		else
			setDHCPCD
			${SUDO} ip addr replace dev "$piholeInterface" "$IPv4addr"
			echo ":::"
			echo "::: Setting IP to $IPv4addr.  You may need to restart after the install is complete."
			echo ":::"
		fi
	elif [[ -f /etc/sysconfig/network-scripts/ifcfg-${piholeInterface} ]];then
		# Fedora Family
		IFCFG_FILE=/etc/sysconfig/network-scripts/ifcfg-${piholeInterface}
		if grep -q "$IPv4addr" ${IFCFG_FILE}; then
			echo "::: Static IP already configured"
		else
			IPADDR=$(echo ${IPv4addr} | cut -f1 -d/)
			CIDR=$(echo ${IPv4addr} | cut -f2 -d/)
			# Backup existing interface configuration:
			cp ${IFCFG_FILE} ${IFCFG_FILE}.backup-$(date +%Y-%m-%d-%H%M%S)
			# Build Interface configuration file:
			${SUDO} echo "# Configured via Pi-Hole installer" > ${IFCFG_FILE}
			${SUDO} echo "DEVICE=$piholeInterface" >> ${IFCFG_FILE}
			${SUDO} echo "BOOTPROTO=none" >> ${IFCFG_FILE}
			${SUDO} echo "ONBOOT=yes" >> ${IFCFG_FILE}
			${SUDO} echo "IPADDR=$IPADDR" >> ${IFCFG_FILE}
			${SUDO} echo "PREFIX=$CIDR" >> ${IFCFG_FILE}
			${SUDO} echo "GATEWAY=$IPv4gw" >> ${IFCFG_FILE}
			${SUDO} echo "DNS1=$piholeDNS1" >> ${IFCFG_FILE}
			${SUDO} echo "DNS2=$piholeDNS2" >> ${IFCFG_FILE}
			${SUDO} echo "USERCTL=no" >> ${IFCFG_FILE}
			${SUDO} ip addr replace dev "$piholeInterface" "$IPv4addr"
			if [ -x "$(command -v nmcli)" ];then
				# Tell NetworkManager to read our new sysconfig file
				${SUDO} nmcli con load ${IFCFG_FILE} > /dev/null
			fi
			echo ":::"
			echo "::: Setting IP to $IPv4addr.  You may need to restart after the install is complete."
			echo ":::"

		fi
	else
		echo "::: Warning: Unable to locate configuration file to set static IPv4 address!"
		exit 1
	fi
}

function valid_ip()
{
	local  ip=$1
	local  stat=1

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

setDNS(){
	DNSChoseCmd=(whiptail --separate-output --radiolist "Select Upstream DNS Provider. To use your own, select Custom." ${r} ${c} 6)
	DNSChooseOptions=(Google "" on
			OpenDNS "" off
			Level3 "" off
			Norton "" off
			Comodo "" off
			Custom "" off)
	DNSchoices=$("${DNSChoseCmd[@]}" "${DNSChooseOptions[@]}" 2>&1 >/dev/tty)
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
                until [[ ${DNSSettingsCorrect} = True ]]
                do
                    strInvalid="Invalid"
                    if [ ! ${piholeDNS1} ]; then
                        if [ ! ${piholeDNS2} ]; then
                            prePopulate=""
                        else
                            prePopulate=", $piholeDNS2"
                        fi
                    elif  [ ${piholeDNS1} ] && [ ! ${piholeDNS2} ]; then
                        prePopulate="$piholeDNS1"
                    elif [ ${piholeDNS1} ] && [ ${piholeDNS2} ]; then
                        prePopulate="$piholeDNS1, $piholeDNS2"
                    fi
                    piholeDNS=$(whiptail --backtitle "Specify Upstream DNS Provider(s)"  --inputbox "Enter your desired upstream DNS provider(s), seperated by a comma.\n\nFor example '8.8.8.8, 8.8.4.4'" ${r} ${c} "$prePopulate" 3>&1 1>&2 2>&3)
                    if [[ $? = 0 ]];then
                        piholeDNS1=$(echo "$piholeDNS" | sed 's/[, \t]\+/,/g' | awk -F, '{print$1}')
                        piholeDNS2=$(echo "$piholeDNS" | sed 's/[, \t]\+/,/g' | awk -F, '{print$2}')
                        if ! valid_ip "$piholeDNS1" || [ ! "$piholeDNS1" ]; then
                            piholeDNS1=${strInvalid}
                        fi
                        if ! valid_ip "$piholeDNS2" && [ "$piholeDNS2" ]; then
                            piholeDNS2=${strInvalid}
                        fi
                    else
                        echo "::: Cancel selected, exiting...."
                        exit 1
                    fi
                    if [[ ${piholeDNS1} == "$strInvalid" ]] || [[ ${piholeDNS2} == "$strInvalid" ]]; then
                        whiptail --msgbox --backtitle "Invalid IP" --title "Invalid IP" "One or both entered IP addresses were invalid. Please try again.\n\n    DNS Server 1:   $piholeDNS1\n    DNS Server 2:   $piholeDNS2" ${r} ${c}
                        if [[ ${piholeDNS1} == "$strInvalid" ]]; then
                            piholeDNS1=""
                        fi
                        if [[ ${piholeDNS2} == "$strInvalid" ]]; then
                            piholeDNS2=""
                        fi
                        DNSSettingsCorrect=False
                    else
                        if (whiptail --backtitle "Specify Upstream DNS Provider(s)" --title "Upstream DNS Provider(s)" --yesno "Are these settings correct?\n    DNS Server 1:   $piholeDNS1\n    DNS Server 2:   $piholeDNS2" ${r} ${c}); then
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

versionCheckDNSmasq(){
	# Check if /etc/dnsmasq.conf is from pihole.  If so replace with an original and install new in .d directory
	dnsFile1="/etc/dnsmasq.conf"
	dnsFile2="/etc/dnsmasq.conf.orig"
	dnsSearch="addn-hosts=/etc/pihole/gravity.list"
	defaultFile="/etc/.pihole/advanced/dnsmasq.conf.original"
	newFileToInstall="/etc/.pihole/advanced/01-pihole.conf"
	newFileFinalLocation="/etc/dnsmasq.d/01-pihole.conf"

	if [ -f ${dnsFile1} ]; then
		echo -n ":::    Existing dnsmasq.conf found..."
		if grep -q ${dnsSearch} ${dnsFile1}; then
			echo " it is from a previous pi-hole install."
			echo -n ":::    Backing up dnsmasq.conf to dnsmasq.conf.orig..."
			${SUDO} mv -f ${dnsFile1} ${dnsFile2}
			echo " done."
			echo -n ":::    Restoring default dnsmasq.conf..."
			${SUDO} cp ${defaultFile} ${dnsFile1}
			echo " done."
		else
			echo " it is not a pi-hole file, leaving alone!"
		fi
	else
		echo -n ":::    No dnsmasq.conf found.. restoring default dnsmasq.conf..."
		${SUDO} cp ${defaultFile} ${dnsFile1}
		echo " done."
	fi

	echo -n ":::    Copying 01-pihole.conf to /etc/dnsmasq.d/01-pihole.conf..."
	${SUDO} cp ${newFileToInstall} ${newFileFinalLocation}
	echo " done."
	${SUDO} sed -i "s/@INT@/$piholeInterface/" ${newFileFinalLocation}
	if [[ "$piholeDNS1" != "" ]]; then
		${SUDO} sed -i "s/@DNS1@/$piholeDNS1/" ${newFileFinalLocation}
	else
		${SUDO} sed -i '/^server=@DNS1@/d' ${newFileFinalLocation}
	fi
	if [[ "$piholeDNS2" != "" ]]; then
		${SUDO} sed -i "s/@DNS2@/$piholeDNS2/" ${newFileFinalLocation}
	else
		${SUDO} sed -i '/^server=@DNS2@/d' ${newFileFinalLocation}
	fi
	${SUDO} sed -i 's/^#conf-dir=\/etc\/dnsmasq.d$/conf-dir=\/etc\/dnsmasq.d/' ${dnsFile1}
}

installScripts() {
	# Install the scripts from /etc/.pihole to their various locations
	${SUDO} echo ":::"
	${SUDO} echo -n "::: Installing scripts to /opt/pihole..."
	if [ ! -d /opt/pihole ]; then
		${SUDO} mkdir /opt/pihole
		${SUDO} chown "$USER":root /opt/pihole
		${SUDO} chmod u+srwx /opt/pihole
	fi
	${SUDO} cp /etc/.pihole/gravity.sh /opt/pihole/gravity.sh
	${SUDO} cp /etc/.pihole/advanced/Scripts/chronometer.sh /opt/pihole/chronometer.sh
	${SUDO} cp /etc/.pihole/advanced/Scripts/whitelist.sh /opt/pihole/whitelist.sh
	${SUDO} cp /etc/.pihole/advanced/Scripts/blacklist.sh /opt/pihole/blacklist.sh
	${SUDO} cp /etc/.pihole/advanced/Scripts/piholeDebug.sh /opt/pihole/piholeDebug.sh
	${SUDO} cp /etc/.pihole/advanced/Scripts/piholeLogFlush.sh /opt/pihole/piholeLogFlush.sh
	${SUDO} cp /etc/.pihole/automated\ install/uninstall.sh /opt/pihole/uninstall.sh
	${SUDO} cp /etc/.pihole/advanced/Scripts/setupLCD.sh /opt/pihole/setupLCD.sh
	${SUDO} cp /etc/.pihole/advanced/Scripts/version.sh /opt/pihole/version.sh
	${SUDO} chmod 755 /opt/pihole/gravity.sh /opt/pihole/chronometer.sh /opt/pihole/whitelist.sh /opt/pihole/blacklist.sh /opt/pihole/piholeLogFlush.sh /opt/pihole/uninstall.sh /opt/pihole/setupLCD.sh /opt/pihole/version.sh
	${SUDO} cp /etc/.pihole/pihole /usr/local/bin/pihole
	${SUDO} chmod 755 /usr/local/bin/pihole
	${SUDO} cp /etc/.pihole/advanced/bash-completion/pihole /etc/bash_completion.d/pihole
	. /etc/bash_completion.d/pihole

	#Tidy up /usr/local/bin directory if installing over previous install.
	oldFiles=( gravity chronometer whitelist blacklist piholeLogFlush updateDashboard uninstall setupLCD piholeDebug)
	for i in "${oldFiles[@]}"; do
		if [ -f "/usr/local/bin/$i.sh" ]; then
			${SUDO} rm /usr/local/bin/"$i".sh
		fi
	done

	${SUDO} echo " done."
}

installConfigs() {
	# Install the configs from /etc/.pihole to their various locations
	${SUDO} echo ":::"
	${SUDO} echo "::: Installing configs..."
	versionCheckDNSmasq
	if [ ! -d "/etc/lighttpd" ]; then
		${SUDO} mkdir /etc/lighttpd
		${SUDO} chown "$USER":root /etc/lighttpd
		${SUDO} mv /etc/lighttpd/lighttpd.conf /etc/lighttpd/lighttpd.conf.orig
	fi
	${SUDO} cp /etc/.pihole/advanced/${LIGHTTPD_CFG} /etc/lighttpd/lighttpd.conf
	${SUDO} mkdir -p /var/run/lighttpd
	${SUDO} chown ${LIGHTTPD_USER}:${LIGHTTPD_GROUP} /var/run/lighttpd
	${SUDO} mkdir -p /var/cache/lighttpd/compress
	${SUDO} chown ${LIGHTTPD_USER}:${LIGHTTPD_GROUP} /var/cache/lighttpd/compress
}

stopServices() {
	# Stop dnsmasq and lighttpd
	${SUDO} echo ":::"
	${SUDO} echo -n "::: Stopping services..."
	#$SUDO service dnsmasq stop & spinner $! || true
	if [ -x "$(command -v systemctl)" ]; then
		${SUDO} systemctl stop lighttpd & spinner $! || true
	else
		${SUDO} service lighttpd stop & spinner $! || true
	fi
	${SUDO} echo " done."
}

installerDependencies() {
	#Running apt-get update/upgrade with minimal output can cause some issues with
	#requiring user input (e.g password for phpmyadmin see #218)
	#We'll change the logic up here, to check to see if there are any updates availible and
	# if so, advise the user to run apt-get update/upgrade at their own discretion
	#Check to see if apt-get update has already been run today
	# it needs to have been run at least once on new installs!
	timestamp=$(stat -c %Y ${PKG_CACHE})
	timestampAsDate=$(date -d @"$timestamp" "+%b %e")
	today=$(date "+%b %e")

	if [ ! "$today" == "$timestampAsDate" ]; then
		#update package lists
		echo ":::"
		echo -n "::: $PKG_MANAGER update has not been run today. Running now..."
		${SUDO} ${UPDATE_PKG_CACHE} > /dev/null 2>&1
		echo " done!"
	fi
	echo ":::"
	echo -n "::: Checking $PKG_MANAGER for upgraded packages...."
	updatesToInstall=$(eval "${SUDO} ${PKG_COUNT}")
	echo " done!"
	echo ":::"
	if [[ ${updatesToInstall} -eq "0" ]]; then
		echo "::: Your pi is up to date! Continuing with pi-hole installation..."
	else
		echo "::: There are $updatesToInstall updates availible for your pi!"
		echo "::: We recommend you run '$PKG_UPDATE' after installing Pi-Hole! "
		echo ":::"
	fi
	echo ":::"
	echo "::: Checking installer dependencies..."
	for i in "${INSTALLER_DEPS[@]}"; do
		echo -n ":::    Checking for $i..."
		package_check ${i} > /dev/null
		if ! [ $? -eq 0 ]; then
			echo -n " Not found! Installing...."
			${SUDO} ${PKG_INSTALL} "$i" > /dev/null 2>&1
			echo " done!"
		else
			echo " already installed!"
		fi
	done
}

checkForDependencies() {
	# Install dependencies for Pi-Hole
    echo "::: Checking Pi-Hole dependencies:"

    for i in "${PIHOLE_DEPS[@]}"; do
	echo -n ":::    Checking for $i..."
	package_check ${i} > /dev/null
	if ! [ $? -eq 0 ]; then
		echo -n " Not found! Installing...."
		${SUDO} ${PKG_INSTALL} "$i" > /dev/null & spinner $!
		echo " done!"
	else
		echo " already installed!"
	fi
    done
}

getGitFiles() {
	# Setup git repos for base files and web admin
	echo ":::"
	echo "::: Checking for existing base files..."
	if is_repo ${piholeFilesDir}; then
		make_repo ${piholeFilesDir} ${piholeGitUrl}
	else
		update_repo ${piholeFilesDir}
	fi

	echo ":::"
	echo "::: Checking for existing web interface..."
	if is_repo ${webInterfaceDir}; then
		make_repo ${webInterfaceDir} ${webInterfaceGitUrl}
	else
		update_repo ${webInterfaceDir}
	fi
}

is_repo() {
	# If the directory does not have a .git folder it is not a repo
	echo -n ":::    Checking $1 is a repo..."
		if [ -d "$1/.git" ]; then
		echo " OK!"
		return 1
	fi
	echo " not found!!"
	return 0
}

make_repo() {
    # Remove the non-repod interface and clone the interface
    echo -n ":::    Cloning $2 into $1..."
    ${SUDO} rm -rf "$1"
    ${SUDO} git clone -q "$2" "$1" > /dev/null & spinner $!
    echo " done!"
}

update_repo() {
    # Pull the latest commits
    echo -n ":::     Updating repo in $1..."
    cd "$1" || exit
    ${SUDO} git pull -q > /dev/null & spinner $!
    echo " done!"
}


CreateLogFile() {
	# Create logfiles if necessary
	echo ":::"
	${SUDO}  echo -n "::: Creating log file and changing owner to dnsmasq..."
	if [ ! -f /var/log/pihole.log ]; then
		${SUDO} touch /var/log/pihole.log
		${SUDO} chmod 644 /var/log/pihole.log
		${SUDO} chown dnsmasq:root /var/log/pihole.log
		${SUDO} echo " done!"
	else
		${SUDO}  echo " already exists!"
	fi
}

installPiholeWeb() {
	# Install the web interface
	${SUDO} echo ":::"
	${SUDO} echo -n "::: Installing pihole custom index page..."
	if [ -d "/var/www/html/pihole" ]; then
		${SUDO} echo " Existing page detected, not overwriting"
	else
		${SUDO} mkdir /var/www/html/pihole
		if [ -f /var/www/html/index.lighttpd.html ]; then
			${SUDO} mv /var/www/html/index.lighttpd.html /var/www/html/index.lighttpd.orig
		else
			printf "\n:::\tNo default index.lighttpd.html file found... not backing up"
		fi
		${SUDO} cp /etc/.pihole/advanced/index.* /var/www/html/pihole/.
		${SUDO} echo " done!"
	fi
	# Install Sudoer file
	echo -n "::: Installing sudoer file..."
	${SUDO} mkdir -p /etc/sudoers.d/
	${SUDO} cp /etc/.pihole/advanced/pihole.sudo /etc/sudoers.d/pihole
	${SUDO} chmod 0440 /etc/sudoers.d/pihole
	echo " done!"
}

installCron() {
	# Install the cron job
	${SUDO} echo ":::"
	${SUDO} echo -n "::: Installing latest Cron script..."
	${SUDO} cp /etc/.pihole/advanced/pihole.cron /etc/cron.d/pihole
	${SUDO} echo " done!"
}

runGravity() {
	# Rub gravity.sh to build blacklists
	${SUDO} echo ":::"
	${SUDO} echo "::: Preparing to run gravity.sh to refresh hosts..."
	if ls /etc/pihole/list* 1> /dev/null 2>&1; then
		echo "::: Cleaning up previous install (preserving whitelist/blacklist)"
		${SUDO} rm /etc/pihole/list.*
	fi
	echo "::: Running gravity.sh"
	${SUDO} /opt/pihole/gravity.sh
}

setUser(){
	# Check if user pihole exists and create if not
	echo "::: Checking if user 'pihole' exists..."
	if id -u pihole > /dev/null 2>&1; then
		echo "::: User 'pihole' already exists"
	else
		echo "::: User 'pihole' doesn't exist.  Creating..."
		${SUDO} useradd -r -s /usr/sbin/nologin pihole
	fi
}

configureFirewall() {
	# Allow HTTP and DNS traffic
	if [ -x "$(command -v firewall-cmd)" ]; then
		${SUDO} firewall-cmd --state > /dev/null
		if [[ $? -eq 0 ]]; then
			${SUDO} echo "::: Configuring firewalld for httpd and dnsmasq.."
			${SUDO} firewall-cmd --permanent --add-port=80/tcp
			${SUDO} firewall-cmd --permanent --add-port=53/tcp
			${SUDO} firewall-cmd --permanent --add-port=53/udp
			${SUDO} firewall-cmd --reload
		fi
	elif [ -x "$(command -v iptables)" ]; then
		${SUDO} echo "::: Configuring iptables for httpd and dnsmasq.."
		${SUDO} iptables -A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
		${SUDO} iptables -A INPUT -p tcp -m tcp --dport 53 -j ACCEPT
		${SUDO} iptables -A INPUT -p udp -m udp --dport 53 -j ACCEPT
	else
		${SUDO} echo "::: No firewall detected.. skipping firewall configuration."
	fi
}

finalExports() {
    #If it already exists, lets overwrite it with the new values.
    if [[ -f ${setupVars} ]];then
        ${SUDO} rm ${setupVars}
    fi
    ${SUDO} echo "piholeInterface=${piholeInterface}" >> ${setupVars}
    ${SUDO} echo "IPv4addr=${IPv4addr}" >> ${setupVars}
    ${SUDO} echo "piholeIPv6=${piholeIPv6}" >> ${setupVars}
    ${SUDO} echo "piholeDNS1=${piholeDNS1}" >> ${setupVars}
    ${SUDO} echo "piholeDNS2=${piholeDNS2}" >> ${setupVars}
}


installPihole() {
	# Install base files and web interface
	checkForDependencies # done
	stopServices
	setUser
	${SUDO} mkdir -p /etc/pihole/
	if [ ! -d "/var/www/html" ]; then
		${SUDO} mkdir -p /var/www/html
	fi
	${SUDO} chown ${LIGHTTPD_USER}:${LIGHTTPD_GROUP} /var/www/html
	${SUDO} chmod 775 /var/www/html
	${SUDO} usermod -a -G ${LIGHTTPD_GROUP} pihole
	if [ -x "$(command -v lighty-enable-mod)" ]; then
		${SUDO} lighty-enable-mod fastcgi fastcgi-php > /dev/null
	else
		printf "\n:::\tWarning: 'lighty-enable-mod' utility not found. Please ensure fastcgi is enabled if you experience issues.\n"
	fi

	getGitFiles
	installScripts
	installConfigs
	CreateLogFile
	configureSelinux
	installPiholeWeb
	installCron
	runGravity
	configureFirewall
	finalExports
}

updatePihole() {
	# Install base files and web interface
	checkForDependencies # done
	stopServices
	getGitFiles
	installScripts
	installConfigs
	CreateLogFile
	configureSelinux
	installPiholeWeb
	installCron
	runGravity
	configureFirewall
}

configureSelinux() {
	if [ -x "$(command -v getenforce)" ]; then
		printf "\n::: SELinux Detected\n"
		printf ":::\tChecking for SELinux policy development packages..."
		package_check "selinux-policy-devel" > /dev/null
		if ! [ $? -eq 0 ]; then
			echo -n " Not found! Installing...."
			${SUDO} ${PKG_INSTALL} "selinux-policy-devel" > /dev/null & spinner $!
			echo " done!"
		else
			echo " already installed!"
		fi
		printf "::: Enabling httpd server side includes (SSI).. "
		${SUDO} setsebool -P httpd_ssi_exec on
		if [ $? -eq 0 ]; then
			echo -n "Success"
		fi
		printf "\n:::\tCompiling Pi-Hole SELinux policy..\n"
		${SUDO} checkmodule -M -m -o /etc/pihole/pihole.mod /etc/.pihole/advanced/selinux/pihole.te
		${SUDO} semodule_package -o /etc/pihole/pihole.pp -m /etc/pihole/pihole.mod
		${SUDO} semodule -i /etc/pihole/pihole.pp
		${SUDO} rm -f /etc/pihole/pihole.mod
		${SUDO} semodule -l | grep pihole > /dev/null
		if [ $? -eq 0 ]; then
			printf "::: Successfully installed Pi-Hole SELinux policy\n"
		else
			printf "::: Warning: Pi-Hole SELinux policy did not install correctly!\n"
		fi
	fi
}

displayFinalMessage() {
	# Final completion message to user
	whiptail --msgbox --backtitle "Make it so." --title "Installation Complete!" "Configure your devices to use the Pi-hole as their DNS server using:

IPv4:	${IPv4addr%/*}
IPv6:	$piholeIPv6

If you set a new IP address, you should restart the Pi.

The install log is in /etc/pihole.
View the web interface at http://pi.hole/admin or http://${IPv4addr%/*}/admin" ${r} ${c}
}

updateDialogs(){

  UpdateCmd=(whiptail --separate-output --radiolist "We have detected an existing install.\n\n    Selecting Update will retain settings from the existing install.\n\n    Selecting Install will allow you to enter new settings.\n\n(Highlight desired option, and press space to select!)" ${r} ${c} 2)
  UpdateChoices=(Update "" on
                 Install "" off)
  UpdateChoice=$("${UpdateCmd[@]}" "${UpdateChoices[@]}" 2>&1 >/dev/tty)

  if [[ $? = 0 ]];then
		case ${UpdateChoice} in
            Update)
                echo "::: Updating existing install"
                useUpdateVars=true
                ;;
            Install)
                echo "::: Running complete install script"
                useUpdateVars=false
                ;;
	    esac
	else
		echo "::: Cancel selected. Exiting..."
		exit 1
	fi

}

######## SCRIPT ############
if [[ -f ${setupVars} ]];then
    . ${setupVars}

    if [ "$1" == "pihole" ]; then
        useUpdateVars=true
    else
        updateDialogs
    fi

fi

# Start the installer
# Verify there is enough disk space for the install
if [ $1 = "--force" ]; then
    echo "::: --force passed to script, skipping free disk space verification!"
else
    verifyFreeDiskSpace
fi

# Install packages used by this installation script
installerDependencies

if [[ ${useUpdateVars} == false ]]; then
    welcomeDialogs

    # Find IP used to route to outside world
    findIPRoute
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
${SUDO} mv ${tmpLog} ${instalLogLoc}

if [[ ${useUpdateVars} == false ]]; then
    displayFinalMessage
fi

echo -n "::: Restarting services..."
# Start services
if [ -x "$(command -v systemctl)" ]; then
	${SUDO} systemctl enable dnsmasq
	${SUDO} systemctl restart dnsmasq
	${SUDO} systemctl enable lighttpd
	${SUDO} systemctl start lighttpd
else
	${SUDO} service dnsmasq restart
	${SUDO} service lighttpd start
fi

echo " done."

echo ":::"
if [[ ${useUpdateVars} == false ]]; then
    echo "::: Installation Complete! Configure your devices to use the Pi-hole as their DNS server using:"
    echo ":::     ${IPv4addr%/*}"
    echo ":::     $piholeIPv6"
    echo ":::"
    echo "::: If you set a new IP address, you should restart the Pi."
else
    echo "::: Update complete!"
fi

echo ":::"
echo "::: The install log is located at: /etc/pihole/install.log"
echo "::: View the web interface at http://pi.hole/admin or http://${IPv4addr%/*}/admin"
