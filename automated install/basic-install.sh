#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
#
# (c) 2015 by Jacob Salmela
# This file is part of Pi-hole.
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
IPv4addr=$(ip -o -f inet addr show dev $IPv4dev | awk '{print $4}' | awk 'END {print}')
IPv4gw=$(ip route get 8.8.8.8 | awk '{print $3}')

availableInterfaces=$(ip -o link | awk '{print $2}' | grep -v "lo" | cut -d':' -f1)
dhcpcdFile=/etc/dhcpcd.conf

######## FIRST CHECK ########
# Must be root to install
echo ":::"
if [[ $EUID -eq 0 ]];then
	echo "You are root."
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

if [ -f "/etc/dnsmasq.d/01-pihole.conf" ]; then
		#Likely an existing install
		upgrade=true
	else
	  upgrade=false
fi

####### FUNCTIONS ##########
###All credit for the below function goes to http://fitnr.com/showing-a-bash-spinner.html
spinner(){
        local pid=$1
        local delay=0.001
        local spinstr='/-\|'

        spin='-\|/'
        i=0
        while kill -0 $pid 2>/dev/null
        do
                i=$(( (i+1) %4 ))
                printf "\b${spin:$i:1}"
                sleep .1
        done
        printf "\b"
}




backupLegacyPihole(){
	if [[ -f /etc/dnsmasq.d/adList.conf ]];then
		echo "Original Pi-hole detected.  Initiating sub space transport"
		$SUDO mkdir -p /etc/pihole/original/
		$SUDO mv /etc/dnsmasq.d/adList.conf /etc/pihole/original/adList.conf.$(date "+%Y-%m-%d")
		$SUDO mv /etc/dnsmasq.conf /etc/pihole/original/dnsmasq.conf.$(date "+%Y-%m-%d")
		$SUDO mv /etc/resolv.conf /etc/pihole/original/resolv.conf.$(date "+%Y-%m-%d")
		$SUDO mv /etc/lighttpd/lighttpd.conf /etc/pihole/original/lighttpd.conf.$(date "+%Y-%m-%d")
		$SUDO mv /var/www/pihole/index.html /etc/pihole/original/index.html.$(date "+%Y-%m-%d")
		$SUDO mv /usr/local/bin/gravity.sh /etc/pihole/original/gravity.sh.$(date "+%Y-%m-%d")
	else
		:
	fi
}

welcomeDialogs(){
	# Display the welcome dialog
	whiptail --msgbox --backtitle "Welcome" --title "Pi-hole automated installer" "This installer will transform your Raspberry Pi into a network-wide ad blocker!" $r $c
	
	# Support for a part-time dev
	whiptail --msgbox --backtitle "Plea" --title "Free and open source" "The Pi-hole is free, but powered by your donations:  http://pi-hole.net/donate" $r $c
	
	# Explain the need for a static address
	whiptail --msgbox --backtitle "Initating network interface" --title "Static IP Needed" "The Pi-hole is a SERVER so it needs a STATIC IP ADDRESS to function properly.	
	In the next section, you can choose to use your current network settings (DHCP) or to manually edit them." $r $c
}

chooseInterface(){
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
	
	for desiredInterface in $chooseInterfaceOptions
	do
		piholeInterface=$desiredInterface
		echo "::: Using interface: $piholeInterface"
		echo ${piholeInterface} > /tmp/piholeINT
	done
}


use4andor6(){
	# Let use select IPv4 and/or IPv6
	cmd=(whiptail --separate-output --checklist "Select Protocols" $r $c 2)
	options=(IPv4 "Block ads over IPv4" on
	IPv6 "Block ads over IPv6" off)
	choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
	for choice in $choices
	do
		case $choice in
		IPv4	)		useIPv4=true;;
		IPv6	)		useIPv6=true;;
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
}

useIPv6dialog(){
	piholeIPv6=$(ip -6 route get 2001:4860:4860::8888 | awk -F " " '{ for(i=1;i<=NF;i++) if ($i == "src") print $(i+1) }')
	whiptail --msgbox --backtitle "IPv6..." --title "IPv6 Supported" "$piholeIPv6 will be used to block ads." $r $c
	$SUDO mkdir -p /etc/pihole/
	$SUDO touch /etc/pihole/.useIPv6
}

getStaticIPv4Settings(){
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
			IPv4addr=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 address" --inputbox "Enter your desired IPv4 address" $r $c $IPv4addr 3>&1 1>&2 2>&3)
			if [[ $? = 0 ]];then
				echo "Your static IPv4 address:    $IPv4addr"
				# Ask for the gateway
				IPv4gw=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 gateway (router)" --inputbox "Enter your desired IPv4 default gateway" $r $c $IPv4gw 3>&1 1>&2 2>&3)
				if [[ $? = 0 ]];then
					echo "Your static IPv4 gateway:    $IPv4gw"
					# Give the user a chance to review their settings before moving on
					if (whiptail --backtitle "Calibrating network interface" --title "Static IP Address" --yesno "Are these settings correct?
							IP address:    $IPv4addr
							Gateway:       $IPv4gw" $r $c)then
							# If the settings are correct, then we need to set the piholeIP
							# Saving it to a temporary file us to retrieve it later when we run the gravity.sh script
							echo ${IPv4addr%/*} > /tmp/piholeIP
							echo $piholeInterface > /tmp/piholeINT
							# After that's done, the loop ends and we move on
							ipSettingsCorrect=True
					else
						# If the settings are wrong, the loop continues
						ipSettingsCorrect=False
					fi
				else
					# Cancelling gateway settings window
					ipSettingsCorrect=False
					echo "User canceled."
					exit
				fi
			else
				# Cancelling IPv4 settings window
				ipSettingsCorrect=False
				echo "User canceled."
				exit
			fi
		done
	# End the if statement for DHCP vs. static
	fi
}

setDHCPCD(){
	#Append these lines to dhcpcd.conf to enable a static IP
	echo "interface $piholeInterface
	static ip_address=$IPv4addr
	static routers=$IPv4gw
	static domain_name_servers=$IPv4gw" | $SUDO tee -a $dhcpcdFile >/dev/null
}

setStaticIPv4(){
	if grep -q $IPv4addr $dhcpcdFile; then
		# address already set, noop
		:
	else
		setDHCPCD
		$SUDO ip addr replace dev $piholeInterface $IPv4addr
		echo "Setting IP to $IPv4addr.  You may need to restart after the install is complete."
	fi
}

installScripts(){
	$SUDO echo ":::"
	$SUDO echo -n "::: Installing scripts..."
	$SUDO cp /etc/.pihole/gravity.sh /usr/local/bin/gravity.sh	
	$SUDO cp /etc/.pihole/advanced/Scripts/chronometer.sh /usr/local/bin/chronometer.sh
	$SUDO cp /etc/.pihole/advanced/Scripts/whitelist.sh /usr/local/bin/whitelist.sh 
	$SUDO cp /etc/.pihole/advanced/Scripts/blacklist.sh /usr/local/bin/blacklist.sh 
	$SUDO cp /etc/.pihole/advanced/Scripts/piholeLogFlush.sh /usr/local/bin/piholeLogFlush.sh 
	$SUDO cp /etc/.pihole/advanced/Scripts/updateDashboard.sh /usr/local/bin/updateDashboard.sh 
	$SUDO chmod 755 /usr/local/bin/{gravity,chronometer,whitelist,blacklist,piholeLogFlush,updateDashboard}.sh
	$SUDO echo " done."
}

installConfigs(){
	$SUDO echo ":::"
	$SUDO echo -n "::: Installing configs..."
	$SUDO mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
	$SUDO mv /etc/lighttpd/lighttpd.conf /etc/lighttpd/lighttpd.conf.orig
	$SUDO cp /etc/.pihole/advanced/dnsmasq.conf /etc/dnsmasq.conf 
	$SUDO cp /etc/.pihole/advanced/lighttpd.conf /etc/lighttpd/lighttpd.conf 
	$SUDO sed -i "s/@INT@/$piholeInterface/" /etc/dnsmasq.conf
	$SUDO echo " done."
}

stopServices(){
	$SUDO echo ":::"
	$SUDO echo -n "::: Stopping services..."
	$SUDO service dnsmasq stop & spinner $! || true 
	$SUDO service lighttpd stop & spinner $! || true 
	$SUDO echo " done."
}


checkForDependencies(){
 		echo ":::" 		
 		#Check to see if apt-get update has already been run today
 		timestamp=$(stat -c %Y /var/cache/apt/)
 		timestampAsDate=$(date -d @$timestamp "+%b %e")
 		today=$(date "+%b %e")
 		
 		if [ ! "$today" == "$timestampAsDate" ]; then 		
	    #update package lists
	    echo -n "::: Updating package list before install...."
	    $SUDO apt-get -qq update > /dev/null & spinner $!
	    echo " done!"
	    echo -n "::: Upgrading installed apt-get packages...."
	    $SUDO apt-get -y -qq upgrade > /dev/null & spinner $!
	    echo " done!"
    else
    	echo "::: Apt-get update already run today, any more would be overkill..."    
    fi
    
    
    echo ":::" 
    echo "::: Checking dependencies:"

    dependencies=( dnsutils bc toilet figlet dnsmasq lighttpd php5-common php5-cgi php5 git curl unzip wget )
    for i in "${dependencies[@]}"
    do
       :
      echo -n ":::    Checking for $i..."
      if [ $(dpkg-query -W -f='${Status}' $i 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
          echo -n " Not found! Installing...."
          apt-get -y -qq install $i > /dev/null  & spinner $!
          echo " done!"
      else
          echo " already installed!"
      fi
    done

}

getGitFiles(){
  
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
		echo -n ":::    Checking $1 is a repo..."
    # if the directory does not have a .git folder 
    # it is not a repo
    if [ -d "$1/.git" ]; then
    		echo " OK!"
        return 1
    fi
    echo " not found!!"
    return 0
    
}

make_repo() {
    # remove the non-repod interface and clone the interface
    echo -n ":::    Cloning $2 into $1..."
    $SUDO rm -rf $1
    $SUDO git clone -q "$2" "$1" > /dev/null & spinner $!
    echo " done!"
}

update_repo() {
    # pull the latest commits
    echo -n ":::     Updating repo in $1..."
    cd "$1"
    $SUDO git pull -q > /dev/null & spinner $!
    echo " done!"
}


CreateLogFile(){
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

installPiholeWeb(){
	$SUDO echo ":::"
	$SUDO echo -n "::: Installing pihole custom index page..."
	if [ -d "/var/www/html/pihole" ]; then
		$SUDO echo " Existing page detected, not overwriting"
	else
		$SUDO mkdir /var/www/html/pihole
		$SUDO mv /var/www/html/index.lighttpd.html /var/www/html/index.lighttpd.orig
		$SUDO cp /etc/.pihole/advanced/index.html /var/www/html/pihole/index.html
		$SUDO echo " done!"
	fi
	
}

installCron(){
	$SUDO echo ":::"
	$SUDO echo -n "::: Installing latest Cron script..."
	$SUDO cp /etc/.pihole/advanced/pihole.cron /etc/cron.d/pihole
	$SUDO echo " done!"
}

runGravity(){
	$SUDO echo ":::"
	$SUDO echo "::: Preparing to run gravity.sh to refresh hosts..."
	if ls /etc/pihole/list* 1> /dev/null 2>&1; then
		echo "::: Cleaning up previous install (preserving whitelist/blacklist)"
		$SUDO rm /etc/pihole/list.*
	fi
	#Don't run as SUDO, this was causing issues
	echo "::: Running gravity.sh"
	echo ":::"
	
	/usr/local/bin/gravity.sh
	
}


installPihole(){
	checkForDependencies # done
	stopServices
	
	$SUDO chown www-data:www-data /var/www/html
	$SUDO chmod 775 /var/www/html
	$SUDO usermod -a -G www-data pi
	$SUDO lighty-enable-mod fastcgi fastcgi-php > /dev/null
	
	getGitFiles	
	installScripts
	installConfigs
	#installWebAdmin
	CreateLogFile
	installPiholeWeb
	installCron
	runGravity
}

displayFinalMessage(){
whiptail --msgbox --backtitle "Make it so." --title "Installation Complete!" "Configure your devices to use the Pi-hole as their DNS server using:

$IPv4addr
$piholeIPv6

If you set a new IP address, you should restart the Pi.

The install log is in /etc/pihole." $r $c
}

######## SCRIPT ############
# Start the installer
welcomeDialogs

# Just back up the original Pi-hole right away since it won't take long and it gets it out of the way
backupLegacyPihole
# Find interfaces and let the user choose one
chooseInterface
# Let the user decide if they want to block ads over IPv4 and/or IPv6
use4andor6



# Install and log everything to a file
installPihole | tee $tmpLog

# Move the log file into /etc/pihole for storage
$SUDO mv $tmpLog $instalLogLoc

displayFinalMessage

$SUDO service dnsmasq start
$SUDO service lighttpd start
