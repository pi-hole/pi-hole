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

webInterfaceGitUrl="https://github.com/pi-hole/AdminLTE.git"
webInterfaceDir="/var/www/html/admin"
piholeGitUrl="https://github.com/pi-hole/pi-hole.git"
piholeFilesDir="/etc/.pihole"


# Find the rows and columns
rows=$(tput lines)
columns=$(tput cols)

# Divide by two so the dialogs take up half of the screen, which looks nice.
r=$(( rows / 2 ))
c=$(( columns / 2 ))


# Find IP used to route to outside world

IPv4dev=$(ip route get 8.8.8.8 | awk '{for(i=1;i<=NF;i++)if($i~/dev/)print $(i+1)}')
IPv4addr=$(ip -o -f inet addr show dev "$IPv4dev" | awk '{print $4}' | awk 'END {print}')
IPv4gw=$(ip route get 8.8.8.8 | awk '{print $3}')

availableInterfaces=$(ip -o link | awk '{print $2}' | grep -v "lo" | cut -d':' -f1)
dhcpcdFile=/etc/dhcpcd.conf

######## FIRST CHECK ########
# Must be root to install
echo ":::"
if [[ $EUID -eq 0 ]];then
	echo "::: You are root."
else
	echo "::: sudo will be used for the install."
	# Check if it is actually installed
	# If it isn't, exit because the install cannot complete
	if [[ $(dpkg-query -s sudo) ]];then
		export SUDO="sudo"
	else
		echo "::: Please install sudo or run this as root."
		exit 1
	fi
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
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

backupLegacyPihole() {
	# This function detects and backups the pi-hole v1 files.  It will not do anything to the current version files.
	if [[ -f /etc/dnsmasq.d/adList.conf ]];then
		echo "::: Original Pi-hole detected.  Initiating sub space transport"
		$SUDO mkdir -p /etc/pihole/original/
		$SUDO mv /etc/dnsmasq.d/adList.conf /etc/pihole/original/adList.conf."$(date "+%Y-%m-%d")"
		$SUDO mv /etc/dnsmasq.conf /etc/pihole/original/dnsmasq.conf."$(date "+%Y-%m-%d")"
		$SUDO mv /etc/resolv.conf /etc/pihole/original/resolv.conf."$(date "+%Y-%m-%d")"
		$SUDO mv /etc/lighttpd/lighttpd.conf /etc/pihole/original/lighttpd.conf."$(date "+%Y-%m-%d")"
		$SUDO mv /var/www/pihole/index.html /etc/pihole/original/index.html."$(date "+%Y-%m-%d")"
		if [ ! -d /opt/pihole ]; then
			$SUDO mkdir /opt/pihole
			$SUDO chown "$USER":root /opt/pihole
			$SUDO chmod u+srwx /opt/pihole
		fi
		$SUDO mv /opt/pihole/gravity.sh /etc/pihole/original/gravity.sh."$(date "+%Y-%m-%d")"
	else
		:
	fi
}

welcomeDialogs() {
	# Display the welcome dialog
	whiptail --msgbox --backtitle "Welcome" --title "Pi-hole automated installer" "This installer will transform your Raspberry Pi into a network-wide ad blocker!" $r $c

	# Support for a part-time dev
	whiptail --msgbox --backtitle "Plea" --title "Free and open source" "The Pi-hole is free, but powered by your donations:  http://pi-hole.net/donate" $r $c

	# Explain the need for a static address
	whiptail --msgbox --backtitle "Initating network interface" --title "Static IP Needed" "The Pi-hole is a SERVER so it needs a STATIC IP ADDRESS to function properly.
	
In the next section, you can choose to use your current network settings (DHCP) or to manually edit them." $r $c
}


verifyFreeDiskSpace() {
	# 50MB is the minimum space needed (45MB install (includes web admin bootstrap/jquery libraries etc) + 5MB one day of logs.)
	requiredFreeBytes=51200

	existingFreeBytes=$(df -lk / 2>&1 | awk '{print $4}' | head -2 | tail -1)
	if ! [[ "$existingFreeBytes" =~ ^([0-9])+$ ]]; then
		existingFreeBytes=$(df -lk /dev 2>&1 | awk '{print $4}' | head -2 | tail -1)
	fi

	if [[ $existingFreeBytes -lt $requiredFreeBytes ]]; then
		whiptail --msgbox --backtitle "Insufficient Disk Space" --title "Insufficient Disk Space" "\nYour system appears to be low on disk space. pi-hole recomends a minimum of $requiredFreeBytes Bytes.\nYou only have $existingFreeBytes Free.\n\nIf this is a new install you may need to expand your disk.\n\nTry running:\n    'sudo raspi-config'\nChoose the 'expand file system option'\n\nAfter rebooting, run this installation again.\n\ncurl -L install.pi-hole.net | bash\n" $r $c
		echo "$existingFreeBytes is less than $requiredFreeBytes"
		echo "Insufficient free space, exiting..."
		exit 1
	fi
}


chooseInterface() {
	# Turn the available interfaces into an array so it can be used with a whiptail dialog
	interfacesArray=()
	firstloop=1

	while read -r line
	do
		mode="OFF"
		if [[ $firstloop -eq 1 ]]; then
			firstloop=0
			mode="ON"
		fi
		interfacesArray+=("$line" "available" "$mode")
	done <<< "$availableInterfaces"

	# Find out how many interfaces are available to choose from
	interfaceCount=$(echo "$availableInterfaces" | wc -l)
	chooseInterfaceCmd=(whiptail --separate-output --radiolist "Choose An Interface" $r $c $interfaceCount)
	chooseInterfaceOptions=$("${chooseInterfaceCmd[@]}" "${interfacesArray[@]}" 2>&1 >/dev/tty)
	if [[ $? = 0 ]]; then
		for desiredInterface in $chooseInterfaceOptions
		do
			piholeInterface=$desiredInterface
			echo "::: Using interface: $piholeInterface"
			echo "${piholeInterface}" > /tmp/piholeINT
		done
	else
		echo "::: Cancel selected, exiting...."
		exit 1
	fi

}

cleanupIPv6() {
	# Removes IPv6 indicator file if we are not using IPv6
	if [ -f "/etc/pihole/.useIPv6" ] && [ ! "$useIPv6" ]; then
		rm /etc/pihole/.useIPv6
	fi
}

use4andor6() {
	# Let use select IPv4 and/or IPv6
	cmd=(whiptail --separate-output --checklist "Select Protocols (press space to select)" $r $c 2)
	options=(IPv4 "Block ads over IPv4" on
	IPv6 "Block ads over IPv6" off)
	choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
	if [[ $? = 0 ]];then
		for choice in $choices
		do
			case $choice in
			IPv4  )   useIPv4=true;;
			IPv6  )   useIPv6=true;;
			esac
		done

		if [ $useIPv4 ] && [ ! $useIPv6 ]; then
			getStaticIPv4Settings
			setStaticIPv4
			echo "::: Using IPv4 on $IPv4addr"
			echo "::: IPv6 will NOT be used."
		fi
		if [ ! $useIPv4 ] && [ $useIPv6 ]; then
			useIPv6dialog
			echo "::: IPv4 will NOT be used."
			echo "::: Using IPv6 on $piholeIPv6"
		fi
		if [ $useIPv4 ] && [  $useIPv6 ]; then
			getStaticIPv4Settings
			setStaticIPv4
			useIPv6dialog
			echo "::: Using IPv4 on $IPv4addr"
			echo "::: Using IPv6 on $piholeIPv6"
		fi
		if [ ! $useIPv4 ] && [ ! $useIPv6 ]; then
			echo "::: Cannot continue, neither IPv4 or IPv6 selected"
			echo "::: Exiting"
			exit 1
		fi
		cleanupIPv6
	else
		echo "::: Cancel selected. Exiting..."
		exit 1
	fi
}

useIPv6dialog() {
	# Show the IPv6 address used for blocking
	piholeIPv6=$(ip -6 route get 2001:4860:4860::8888 | awk -F " " '{ for(i=1;i<=NF;i++) if ($i == "src") print $(i+1) }')
	whiptail --msgbox --backtitle "IPv6..." --title "IPv6 Supported" "$piholeIPv6 will be used to block ads." $r $c

	$SUDO touch /etc/pihole/.useIPv6
}

getStaticIPv4Settings() {
	# Ask if the user wants to use DHCP settings as their static IP
	if (whiptail --backtitle "Calibrating network interface" --title "Static IP Address" --yesno "Do you want to use your current network settings as a static address?
					IP address:    $IPv4addr
					Gateway:       $IPv4gw" $r $c) then
		# If they choose yes, let the user know that the IP address will not be available via DHCP and may cause a conflict.
		whiptail --msgbox --backtitle "IP information" --title "FYI: IP Conflict" "It is possible your router could still try to assign this IP to a device, which would cause a conflict.  But in most cases the router is smart enough to not do that.
If you are worried, either manually set the address, or modify the DHCP reservation pool so it does not include the IP you want.
It is also possible to use a DHCP reservation, but if you are going to do that, you might as well set a static address." $r $c
		# Nothing else to do since the variables are already set above
	else
		# Otherwise, we need to ask the user to input their desired settings.
		# Start by getting the IPv4 address (pre-filling it with info gathered from DHCP)
		# Start a loop to let the user enter their information with the chance to go back and edit it if necessary
		until [[ $ipSettingsCorrect = True ]]
		do
			# Ask for the IPv4 address
			IPv4addr=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 address" --inputbox "Enter your desired IPv4 address" $r $c "$IPv4addr" 3>&1 1>&2 2>&3)
			if [[ $? = 0 ]];then
			echo "::: Your static IPv4 address:    $IPv4addr"
			# Ask for the gateway
			IPv4gw=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 gateway (router)" --inputbox "Enter your desired IPv4 default gateway" $r $c "$IPv4gw" 3>&1 1>&2 2>&3)
			if [[ $? = 0 ]];then
				echo "::: Your static IPv4 gateway:    $IPv4gw"
				# Give the user a chance to review their settings before moving on
				if (whiptail --backtitle "Calibrating network interface" --title "Static IP Address" --yesno "Are these settings correct?
					IP address:    $IPv4addr
					Gateway:       $IPv4gw" $r $c)then
					# If the settings are correct, then we need to set the piholeIP
					# Saving it to a temporary file us to retrieve it later when we run the gravity.sh script. piholeIP is saved to a permanent file so gravity.sh can use it when updating
					echo "${IPv4addr%/*}" > /etc/pihole/piholeIP
					echo "$piholeInterface" > /tmp/piholeINT
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
	echo "::: interface $piholeInterface
	static ip_address=$IPv4addr
	static routers=$IPv4gw
	static domain_name_servers=$IPv4gw" | $SUDO tee -a $dhcpcdFile >/dev/null
}

setStaticIPv4() {
	# Tries to set the IPv4 address
	if grep -q "$IPv4addr" $dhcpcdFile; then
		# address already set, noop
		:
	else
		setDHCPCD
		$SUDO ip addr replace dev "$piholeInterface" "$IPv4addr"
		echo ":::"
		echo "::: Setting IP to $IPv4addr.  You may need to restart after the install is complete."
		echo ":::"
	fi
}

function valid_ip()
{
	local  ip=$1
	local  stat=1

	if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		OIFS=$IFS
		IFS='.'
		ip=($ip)
		IFS=$OIFS
		[[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
		&& ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
		stat=$?
	fi
	return $stat
}

setDNS(){
	DNSChoseCmd=(whiptail --separate-output --radiolist "Select Upstream DNS Provider. To use your own, select Custom." $r $c 6)
	DNSChooseOptions=(Google "" on
			OpenDNS "" off
			Level3 "" off
			Norton "" off
			Comodo "" off
			Custom "" off)
	DNSchoices=$("${DNSChoseCmd[@]}" "${DNSChooseOptions[@]}" 2>&1 >/dev/tty)
	if [[ $? = 0 ]];then
		case $DNSchoices in
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
			until [[ $DNSSettingsCorrect = True ]]
			do
				strInvalid="Invalid"
				if [ ! $piholeDNS1 ]; then
					if [ ! $piholeDNS2 ]; then
						prePopulate=""
					else
						prePopulate=", $piholeDNS2"
					fi
				elif  [ $piholeDNS1 ] && [ ! $piholeDNS2 ]; then
					prePopulate="$piholeDNS1"
				elif [ $piholeDNS1 ] && [ $piholeDNS2 ]; then
					prePopulate="$piholeDNS1, $piholeDNS2"
				fi
				piholeDNS=$(whiptail --backtitle "Specify Upstream DNS Provider(s)"  --inputbox "Enter your desired upstream DNS provider(s), seperated by a comma.\n\nFor example '8.8.8.8, 8.8.4.4'" $r $c "$prePopulate" 3>&1 1>&2 2>&3)
				if [[ $? = 0 ]];then
					piholeDNS1=$(echo "$piholeDNS" | sed 's/[, \t]\+/,/g' | awk -F, '{print$1}')
					piholeDNS2=$(echo "$piholeDNS" | sed 's/[, \t]\+/,/g' | awk -F, '{print$2}')
					if ! valid_ip "$piholeDNS1" || [ ! "$piholeDNS1" ]; then
						piholeDNS1=$strInvalid
					fi
					if ! valid_ip "$piholeDNS2" && [ "$piholeDNS2" ]; then
						piholeDNS2=$strInvalid
					fi
				else
					echo "::: Cancel selected, exiting...."
					exit 1
				fi
				if [[ $piholeDNS1 == "$strInvalid" ]] || [[ $piholeDNS2 == "$strInvalid" ]]; then
					whiptail --msgbox --backtitle "Invalid IP" --title "Invalid IP" "One or both entered IP addresses were invalid. Please try again.\n\n    DNS Server 1:   $piholeDNS1\n    DNS Server 2:   $piholeDNS2" $r $c
					if [[ $piholeDNS1 == "$strInvalid" ]]; then
						piholeDNS1=""
					fi
					if [[ $piholeDNS2 == "$strInvalid" ]]; then
						piholeDNS2=""
					fi
					DNSSettingsCorrect=False
				else
					if (whiptail --backtitle "Specify Upstream DNS Provider(s)" --title "Upstream DNS Provider(s)" --yesno "Are these settings correct?\n    DNS Server 1:   $piholeDNS1\n    DNS Server 2:   $piholeDNS2" $r $c) then
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

	if [ -f $dnsFile1 ]; then
		echo -n ":::    Existing dnsmasq.conf found..."
		if grep -q $dnsSearch $dnsFile1; then
			echo " it is from a previous pi-hole install."
			echo -n ":::    Backing up dnsmasq.conf to dnsmasq.conf.orig..."
			$SUDO mv -f $dnsFile1 $dnsFile2
			echo " done."
			echo -n ":::    Restoring default dnsmasq.conf..."
			$SUDO cp $defaultFile $dnsFile1
			echo " done."
		else
			echo " it is not a pi-hole file, leaving alone!"
		fi
	else
		echo -n ":::    No dnsmasq.conf found.. restoring default dnsmasq.conf..."
		$SUDO cp $defaultFile $dnsFile1
		echo " done."
	fi

	echo -n ":::    Copying 01-pihole.conf to /etc/dnsmasq.d/01-pihole.conf..."
	$SUDO cp $newFileToInstall $newFileFinalLocation
	echo " done."
	$SUDO sed -i "s/@INT@/$piholeInterface/" $newFileFinalLocation
	if [[ "$piholeDNS1" != "" ]]; then
		$SUDO sed -i "s/@DNS1@/$piholeDNS1/" $newFileFinalLocation
	else
		$SUDO sed -i '/^server=@DNS1@/d' $newFileFinalLocation
	fi
	if [[ "$piholeDNS2" != "" ]]; then
		$SUDO sed -i "s/@DNS2@/$piholeDNS2/" $newFileFinalLocation
	else
		$SUDO sed -i '/^server=@DNS2@/d' $newFileFinalLocation
	fi
}

installScripts() {
	# Install the scripts from /etc/.pihole to their various locations
	$SUDO echo ":::"
	$SUDO echo -n "::: Installing scripts to /opt/pihole..."
	if [ ! -d /opt/pihole ]; then
		$SUDO mkdir /opt/pihole
		$SUDO chown "$USER":root /opt/pihole
		$SUDO chmod u+srwx /opt/pihole
	fi
	$SUDO cp /etc/.pihole/gravity.sh /opt/pihole/gravity.sh
	$SUDO cp /etc/.pihole/advanced/Scripts/chronometer.sh /opt/pihole/chronometer.sh
	$SUDO cp /etc/.pihole/advanced/Scripts/whitelist.sh /opt/pihole/whitelist.sh
	$SUDO cp /etc/.pihole/advanced/Scripts/blacklist.sh /opt/pihole/blacklist.sh
	$SUDO cp /etc/.pihole/advanced/Scripts/piholeDebug.sh /opt/pihole/piholeDebug.sh
	$SUDO cp /etc/.pihole/advanced/Scripts/piholeLogFlush.sh /opt/pihole/piholeLogFlush.sh
	$SUDO cp /etc/.pihole/advanced/Scripts/updateDashboard.sh /opt/pihole/updateDashboard.sh
	$SUDO cp /etc/.pihole/automated\ install/uninstall.sh /opt/pihole/uninstall.sh
	$SUDO cp /etc/.pihole/advanced/Scripts/setupLCD.sh /opt/pihole/setupLCD.sh
	$SUDO chmod 755 /opt/pihole/{gravity,chronometer,whitelist,blacklist,piholeLogFlush,updateDashboard,uninstall,setupLCD}.sh
	$SUDO cp /etc/.pihole/pihole /usr/local/bin/pihole
	$SUDO chmod 755 /usr/local/bin/pihole
	$SUDO cp /etc/.pihole/advanced/bash-completion/pihole /etc/bash_completion.d/pihole
	. /etc/bash_completion.d/pihole

	#Tidy up /usr/local/bin directory if installing over previous install.
	oldFiles=( gravity chronometer whitelist blacklist piholeLogFlush updateDashboard uninstall setupLCD piholeDebug)
	for i in "${oldFiles[@]}"; do
		if [ -f "/usr/local/bin/$i.sh" ]; then
			$SUDO rm /usr/local/bin/"$i".sh
		fi
	done

	$SUDO echo " done."
}

installConfigs() {
	# Install the configs from /etc/.pihole to their various locations
	$SUDO echo ":::"
	$SUDO echo "::: Installing configs..."
	versionCheckDNSmasq
	if [ ! -d "/etc/lighttpd" ]; then
		$SUDO mkdir /etc/lighttpd
		$SUDO chown "$USER":root /etc/lighttpd
		$SUDO mv /etc/lighttpd/lighttpd.conf /etc/lighttpd/lighttpd.conf.orig
	fi
	$SUDO cp /etc/.pihole/advanced/lighttpd.conf /etc/lighttpd/lighttpd.conf
}

stopServices() {
	# Stop dnsmasq and lighttpd
	$SUDO echo ":::"
	$SUDO echo -n "::: Stopping services..."
	#$SUDO service dnsmasq stop & spinner $! || true
	$SUDO service lighttpd stop & spinner $! || true
	$SUDO echo " done."
}

checkForDependencies() {
	#Running apt-get update/upgrade with minimal output can cause some issues with
	#requiring user input (e.g password for phpmyadmin see #218)
	#We'll change the logic up here, to check to see if there are any updates availible and
	# if so, advise the user to run apt-get update/upgrade at their own discretion
	#Check to see if apt-get update has already been run today
	# it needs to have been run at least once on new installs!

	timestamp=$(stat -c %Y /var/cache/apt/)
	timestampAsDate=$(date -d @"$timestamp" "+%b %e")
	today=$(date "+%b %e")

	if [ ! "$today" == "$timestampAsDate" ]; then
		#update package lists
		echo ":::"
		echo -n "::: apt-get update has not been run today. Running now..."
		$SUDO apt-get -qq update & spinner $!
		echo " done!"
	fi
	echo ":::"
	echo -n "::: Checking apt-get for upgraded packages...."
    updatesToInstall=$($SUDO apt-get -s -o Debug::NoLocking=true upgrade | grep -c ^Inst)
    echo " done!"
    echo ":::"
    if [[ $updatesToInstall -eq "0" ]]; then
		echo "::: Your pi is up to date! Continuing with pi-hole installation..."
    else
		echo "::: There are $updatesToInstall updates availible for your pi!"
		echo "::: We recommend you run 'sudo apt-get upgrade' after installing Pi-Hole! "
		echo ":::"
    fi
    echo ":::"
    echo "::: Checking dependencies:"

  dependencies=( dnsutils bc toilet figlet dnsmasq lighttpd php5-common php5-cgi php5 git curl unzip wget )
	for i in "${dependencies[@]}"; do
		echo -n ":::    Checking for $i..."
		if [ "$(dpkg-query -W -f='${Status}' "$i" 2>/dev/null | grep -c "ok installed")" -eq 0 ]; then
			echo -n " Not found! Installing...."
			$SUDO apt-get -y -qq install "$i" > /dev/null & spinner $!
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
	if is_repo $piholeFilesDir; then
		make_repo $piholeFilesDir $piholeGitUrl
	else
		update_repo $piholeFilesDir
	fi

	echo ":::"
	echo "::: Checking for existing web interface..."
	if is_repo $webInterfaceDir; then
		make_repo $webInterfaceDir $webInterfaceGitUrl
	else
		update_repo $webInterfaceDir
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
    $SUDO rm -rf "$1"
    $SUDO git clone -q "$2" "$1" > /dev/null & spinner $!
    echo " done!"
}

update_repo() {
    # Pull the latest commits
    echo -n ":::     Updating repo in $1..."
    cd "$1" || exit
    $SUDO git pull -q > /dev/null & spinner $!
    echo " done!"
}


CreateLogFile() {
	# Create logfiles if necessary
	echo ":::"
	$SUDO  echo -n "::: Creating log file and changing owner to dnsmasq..."
	if [ ! -f /var/log/pihole.log ]; then
		$SUDO touch /var/log/pihole.log
		$SUDO chmod 644 /var/log/pihole.log
		$SUDO chown dnsmasq:root /var/log/pihole.log
		$SUDO echo " done!"
	else
		$SUDO  echo " already exists!"
	fi
}

installPiholeWeb() {
	# Install the web interface
	$SUDO echo ":::"
	$SUDO echo -n "::: Installing pihole custom index page..."
	if [ -d "/var/www/html/pihole" ]; then
		$SUDO echo " Existing page detected, not overwriting"
	else
		$SUDO mkdir /var/www/html/pihole
		if [ -f /var/www/html/index.lighttpd.html ]; then
			$SUDO mv /var/www/html/index.lighttpd.html /var/www/html/index.lighttpd.orig
		else
			printf "\n:::\tNo default index.lighttpd.html file found... not backing up"
		fi
		$SUDO cp /etc/.pihole/advanced/index.* /var/www/html/pihole/.
		$SUDO echo " done!"
	fi
}

installCron() {
	# Install the cron job
	$SUDO echo ":::"
	$SUDO echo -n "::: Installing latest Cron script..."
	$SUDO cp /etc/.pihole/advanced/pihole.cron /etc/cron.d/pihole
	$SUDO echo " done!"
}

runGravity() {
	# Rub gravity.sh to build blacklists
	$SUDO echo ":::"
	$SUDO echo "::: Preparing to run gravity.sh to refresh hosts..."
	if ls /etc/pihole/list* 1> /dev/null 2>&1; then
		echo "::: Cleaning up previous install (preserving whitelist/blacklist)"
		$SUDO rm /etc/pihole/list.*
	fi
	echo "::: Running gravity.sh"
	$SUDO /opt/pihole/gravity.sh
}

setUser(){
	# Check if user pihole exists and create if not
	echo "::: Checking if user 'pihole' exists..."
	if id -u pihole > /dev/null 2>&1; then
		echo "::: User 'pihole' already exists"
	else
		echo "::: User 'pihole' doesn't exist.  Creating..."
		$SUDO useradd -r -s /usr/sbin/nologin pihole
	fi
}

installPihole() {
	# Install base files and web interface
	checkForDependencies # done
	stopServices
	setUser
	$SUDO mkdir -p /etc/pihole/
	if [ ! -d "/var/www/html" ]; then
		$SUDO mkdir -p /var/www/html
	fi
	$SUDO chown www-data:www-data /var/www/html
	$SUDO chmod 775 /var/www/html
	$SUDO usermod -a -G www-data pihole
	$SUDO lighty-enable-mod fastcgi fastcgi-php > /dev/null

	getGitFiles
	installScripts
	installConfigs
	CreateLogFile
	installPiholeWeb
	installCron
	runGravity
}

displayFinalMessage() {
	# Final completion message to user
	whiptail --msgbox --backtitle "Make it so." --title "Installation Complete!" "Configure your devices to use the Pi-hole as their DNS server using:

IPv4:	$IPv4addr
IPv6:	$piholeIPv6

If you set a new IP address, you should restart the Pi.

The install log is in /etc/pihole." $r $c
}

######## SCRIPT ############
# Start the installer
$SUDO mkdir -p /etc/pihole/
welcomeDialogs

# Verify there is enough disk space for the install
verifyFreeDiskSpace

# Just back up the original Pi-hole right away since it won't take long and it gets it out of the way
backupLegacyPihole
# Find interfaces and let the user choose one
chooseInterface
# Let the user decide if they want to block ads over IPv4 and/or IPv6
use4andor6

# Decide what upstream DNS Servers to use
setDNS

# Install and log everything to a file
installPihole | tee $tmpLog

# Move the log file into /etc/pihole for storage
$SUDO mv $tmpLog $instalLogLoc

displayFinalMessage

echo -n "::: Restarting services..."
# Start services
$SUDO service dnsmasq restart
$SUDO service lighttpd start
echo " done."

echo ":::"
echo "::: Installation Complete! Configure your devices to use the Pi-hole as their DNS server using:"
echo ":::     $IPv4addr"
echo ":::     $piholeIPv6"
echo ":::"
echo "::: If you set a new IP address, you should restart the Pi."
echo "::: "
echo "::: The install log is located at: /etc/pihole/install.log"

