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

# Get the screen size in case we need a full-screen message and so we can display a dialog that is sized nicely
screenSize=$(stty -a | tr \; \\012 | egrep 'rows|columns' | cut '-d ' -f3)

# Find the rows and columns
rows=$(stty -a | tr \; \\012 | egrep 'rows' | cut -d' ' -f3)
columns=$(stty -a | tr \; \\012 | egrep 'columns' | cut -d' ' -f3)

# Divide by two so the dialogs take up half of the screen, which looks nice.
r=$(( rows / 2 ))
c=$(( columns / 2 ))

# Find IP used to route to outside world
IPv4dev=$(ip route get 8.8.8.8 | awk '{for(i=1;i<=NF;i++)if($i~/dev/)print $(i+1)}')
IPv4addr=$(ip -o -f inet addr show dev $IPv4dev | awk '{print $4}' | awk 'END {print}')
IPv4gw=$(ip route get 8.8.8.8 | awk '{print $3}')

availableInterfaces=$(ip -o link | awk '{print $2}' | grep -v "lo" | cut -d':' -f1)
dhcpcdFile=/etc/dhcpcd.conf

####### FUCNTIONS ##########
backupLegacyPihole()
{
if [[ -f /etc/dnsmasq.d/adList.conf ]];then
	echo "Original Pi-hole detected.  Initiating sub space transport"
	sudo mkdir -p /etc/pihole/original/
	sudo mv /etc/dnsmasq.d/adList.conf /etc/pihole/original/adList.conf.$(date "+%Y-%m-%d")
	sudo mv /etc/dnsmasq.conf /etc/pihole/original/dnsmasq.conf.$(date "+%Y-%m-%d")
	sudo mv /etc/resolv.conf /etc/pihole/original/resolv.conf.$(date "+%Y-%m-%d")
	sudo mv /etc/lighttpd/lighttpd.conf /etc/pihole/original/lighttpd.conf.$(date "+%Y-%m-%d")
	sudo mv /var/www/pihole/index.html /etc/pihole/original/index.html.$(date "+%Y-%m-%d")
	sudo mv /usr/local/bin/gravity.sh /etc/pihole/original/gravity.sh.$(date "+%Y-%m-%d")
else
	:
fi
}

welcomeDialogs()
{
# Display the welcome dialog
whiptail --msgbox --backtitle "Welcome" --title "Pi-hole automated installer" "This installer will transform your Raspberry Pi into a network-wide ad blocker!" $r $c

# Support for a part-time dev
whiptail --msgbox --backtitle "Plea" --title "Free and open source" "The Pi-hole is free, but powered by your donations:  http://pi-hole.net/donate" $r $c

# Explain the need for a static address
whiptail --msgbox --backtitle "Initating network interface" --title "Static IP Needed" "The Pi-hole is a SERVER so it needs a STATIC IP ADDRESS to function properly.

In the next section, you can choose to use your current network settings (DHCP) or to manually edit them." $r $c
}

chooseInterface()
{
# Turn the available interfaces into an array so it can be used with a whiptail dialog
interfacesArray=()
while read -r line
do
interfacesArray+=("$line" "available" "ON")
done <<< "$availableInterfaces"

# Find out how many interfaces are available to choose from
interfaceCount=$(echo "$availableInterfaces" | wc -l)
chooseInterfaceCmd=(whiptail --separate-output --radiolist "Choose An Interface" $r $c $interfaceCount)
chooseInterfaceOptions=$("${chooseInterfaceCmd[@]}" "${interfacesArray[@]}" 2>&1 >/dev/tty)
for desiredInterface in $chooseInterfaceOptions
do
	piholeInterface=$desiredInterface
	echo "Using interface: $piholeInterface"
	echo ${piholeInterface} > /tmp/piholeINT
done
}

use4andor6()
{
# Let use select IPv4 and/or IPv6
cmd=(whiptail --separate-output --checklist "Select Protocols" $r $c 2)
options=(IPv4 "Block ads over IPv4" on
         IPv6 "Block ads over IPv6" off)
choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
for choice in $choices
do
    case $choice in
        IPv4)
            echo "IPv4 selected."
			useIPv4=true
            ;;
        IPv6)
			echo "IPv6 selected."
			useIPv6=true
            ;;
    esac
done
}

useIPv6dialog()
{
piholeIPv6=$(ip -6 route get 2001:4860:4860::8888 | awk -F " " '{ for(i=1;i<=NF;i++) if ($i == "src") print $(i+1) }')
whiptail --msgbox --backtitle "IPv6..." --title "IPv6 Supported" "$piholeIPv6 will be used to block ads." $r $c
sudo mkdir -p /etc/pihole/
sudo touch /etc/pihole/.useIPv6
}

getStaticIPv4Settings()
{
# Ask if the user wannts to use DHCP settings as their static IP
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
# Append these lines to dhcpcd.conf to enable a static IP
echo "interface $piholeInterface
static ip_address=$IPv4addr
static routers=$IPv4gw
static domain_name_servers=$IPv4gw" | sudo tee -a $dhcpcdFile >/dev/null
}

setStaticIPv4(){
if grep -q $IPv4addr $dhcpcdFile; then
	# address already set, noop
	:
else
	setDHCPCD
	sudo ip addr replace dev $piholeInterface $IPv4addr
	echo "Setting IP to $IPv4addr.  You may need to restart after the install is complete."
fi
}

installScripts(){
sudo curl -o /usr/local/bin/gravity.sh https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/gravity.sh
sudo curl -o /usr/local/bin/chronometer.sh https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/Scripts/chronometer.sh
sudo curl -o /usr/local/bin/whitelist.sh https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/Scripts/whitelist.sh
sudo curl -o /usr/local/bin/piholeLogFlush.sh https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/Scripts/piholeLogFlush.sh
sudo chmod 755 /usr/local/bin/{gravity,chronometer,whitelist,piholeLogFlush}.sh
}

installConfigs(){
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
sudo mv /etc/lighttpd/lighttpd.conf /etc/lighttpd/lighttpd.conf.orig
sudo curl -o /etc/dnsmasq.conf https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/dnsmasq.conf
sudo curl -o /etc/lighttpd/lighttpd.conf https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/lighttpd.conf
sudo sed -i "s/@INT@/$piholeInterface/" /etc/dnsmasq.conf
}

stopServices(){
sudo service dnsmasq stop || true
sudo service lighttpd stop || true
}

installDependencies(){
sudo apt-get update
sudo apt-get -y upgrade
sudo apt-get -y install dnsutils bc toilet
sudo apt-get -y install dnsmasq
sudo apt-get -y install lighttpd php5-common php5-cgi php5
}

installWebAdmin(){
sudo wget https://github.com/jacobsalmela/AdminLTE/archive/master.zip -O /var/www/master.zip
sudo unzip -oq /var/www/master.zip -d /var/www/html/
sudo mv /var/www/html/AdminLTE-master /var/www/html/admin
sudo rm /var/www/master.zip 2>/dev/null
sudo touch /var/log/pihole.log
sudo chmod 644 /var/log/pihole.log
sudo chown dnsmasq:root /var/log/pihole.log
}

installPiholeWeb(){
sudo mkdir /var/www/html/pihole
sudo mv /var/www/html/index.lighttpd.html /var/www/html/index.lighttpd.orig
sudo curl -o /var/www/html/pihole/index.html https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/index.html
}

installCron(){
sudo mv /etc/crontab /etc/crontab.orig
sudo curl -o /etc/crontab https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/pihole.cron
}

installPihole()
{
installDependencies
stopServices
sudo chown www-data:www-data /var/www/html
sudo chmod 775 /var/www/html
sudo usermod -a -G www-data pi
sudo lighty-enable-mod fastcgi fastcgi-php
installScripts
installConfigs
installWebAdmin
installPiholeWeb
installCron
sudo /usr/local/bin/gravity.sh
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

# Decide is IPv4 will be used
if [[ "$useIPv4" = true ]];then
	echo "Using IPv4"
	getStaticIPv4Settings
	setStaticIPv4
else
	useIPv4=false
	echo "IPv4 will NOT be used."
fi

# Decide is IPv6 will be used
if [[ "$useIPv6" = true ]];then
	useIPv6dialog
	echo "Using IPv6."
	echo "Your IPv6 address is: $piholeIPv6"
else
	useIPv6=false
	echo "IPv6 will NOT be used."
fi

# Install and log everything to a file
installPihole | tee $tmpLog

# Move the log file into /etc/pihole for storage
sudo mv $tmpLog $instalLogLoc

displayFinalMessage

sudo service dnsmasq start
sudo service lighttpd start
