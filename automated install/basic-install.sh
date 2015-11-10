#!/bin/bash
# Pi-hole: A black hole for Internet advertisements
# by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
#
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

IPv4addr=$(ip -4 addr show | awk '{match($0,/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/); ip = substr($0,RSTART,RLENGTH); print ip}' | sed '/^\s*$/d' | grep -v "127.0.0.1")
IPv4mask=$(ifconfig | awk -F':' '/inet addr/ && !/127.0.0.1/ {print $4}')
IPv4gw=$(ip route show | awk '/default\ via/ {print $3}')

# IPv6 support to be added later
#IPv6eui64=$(ip addr show | awk '/scope\ global/ && /ff:fe/ {print $2}' | cut -d'/' -f1)
#IPv6linkLocal=$(ip addr show | awk '/inet/ && /scope\ link/ && /fe80/ {print $2}' | cut -d'/' -f1)

availableInterfaces=$(ip link show | awk -F' ' '/[0-9]: [a-z]/ {print $2}' | grep -v "lo" | cut -d':' -f1)
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
done
}

use4andor6()
{
# Let use select IPv4 and/or IPv6
cmd=(whiptail --separate-output --checklist "Select Protocols" $r $c 2)
options=(IPv4 "Block ads over IPv4" on
         IPv6 "Block ads over IPv4" off)
choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
clear
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
whiptail --msgbox --backtitle "Coming soon..." --title "IPv6 not yet supported" "I need your help for IPv6.  Consider donating at: http://pi-hole.net/donate" $r $c
}

getStaticIPv4Settings()
{
# Ask if the user wannts to use DHCP settings as their static IP
if (whiptail --backtitle "Calibrating network interface" --title "Static IP Address" --yesno "Do you want to use your current network settings as a static address?

								IP address:    $IPv4addr
								Subnet mask:   $IPv4mask
								Gateway:       $IPv4gw" $r $c) then
	# If they choose yes, let the user know that the IP address will not be available via DHCP and may cause a conflict.
	whiptail --msgbox --backtitle "IP information" --title "FYI: IP Conflict" "It is possible your router could still try to assign this IP to a device, which would cause a conflict.  But in most cases the router is smart enough to not do that.

	If you are worried, either manually set the address, or modify the DHCP reservation pool so it does not include the IP you want.

	It is also possible to use a DHCP reservation, but if you are going to do that, you might as well set a static address." $r $c
	# Nothing else to do since the variables are already set above
else
	# Since a custom address will be used, restart at the end of the script to apply the new changes
	rebootNeeded=true
	# Otherwise, we need to ask the user to input their desired settings.
	# Start by getting the IPv4 address (pre-filling it with info gathered from DHCP)
	# Start a loop to let the user enter their information with the chance to go back and edit it if necessary
	until [[ $ipSettingsCorrect = True ]]
	do
	# Ask for the IPv4 address
	IPv4addr=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 address" --inputbox "Enter your desired IPv4 address" $r $c $IPv4addr 3>&1 1>&2 2>&3)
	if [[ $? = 0 ]];then
    	echo "Your static IPv4 address:    $IPv4addr"
		# Ask for the subnet mask
		IPv4mask=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 netmask" --inputbox "Enter your desired IPv4 subnet mask" $r $c $IPv4mask 3>&1 1>&2 2>&3)
		if [[ $? = 0 ]];then
			echo "Your static IPv4 netmask:    $IPv4mask"
			# Ask for the gateway
			IPv4gw=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 gateway (router)" --inputbox "Enter your desired IPv4 default gateway" $r $c $IPv4gw 3>&1 1>&2 2>&3)
			if [[ $? = 0 ]];then
				echo "Your static IPv4 gateway:    $IPv4gw"
				# Give the user a chance to review their settings before moving on
				if (whiptail --backtitle "Calibrating network interface" --title "Static IP Address" --yesno "Are these settings correct?
					IP address:    $IPv4addr
					Subnet mask:   $IPv4mask
					Gateway:       $IPv4gw" $r $c)then
					# If the settings are correct, then we need to set the piholeIP
					# Saving it to a temporary file us to retrieve it later when we run the gravity.sh script
					echo $IPv4addr > /tmp/piholeIP
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
			# Cancelling subnet mask settings window
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


setStaticIPv4()
{
# Append these lines to /etc/dhcpcd.conf to enable a static IP
echo "interface $piholeInterface
static ip_address=$IPv4addr/24
static routers=$IPv4gw
static domain_name_servers=$IPv4gw" | sudo tee -a $dhcpcdFile >/dev/null
}

installPihole()
{
sudo apt-get update
sudo apt-get -y upgrade
sudo apt-get -y install dnsutils bc toilet
sudo apt-get -y install dnsmasq
sudo apt-get -y install lighttpd php5-common php5-cgi php5
sudo mkdir /var/www/html
sudo chown www-data:www-data /var/www/html
sudo chmod 775 /var/www/html
sudo usermod -a -G www-data pi
sudo service dnsmasq stop
sudo service lighttpd stop
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
sudo mv /etc/lighttpd/lighttpd.conf /etc/lighttpd/lighttpd.conf.orig
sudo mv /var/www/html/index.lighttpd.html /var/www/html/index.lighttpd.orig
sudo mv /etc/crontab /etc/crontab.orig
sudo curl -o /etc/dnsmasq.conf https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/dnsmasq.conf
sudo curl -o /etc/lighttpd/lighttpd.conf https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/lighttpd.conf
sudo mv /etc/crontab /etc/crontab.orig
sudo curl -o /etc/crontab https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/pihole.cron
sudo lighty-enable-mod fastcgi fastcgi-php
sudo mkdir /var/www/html/pihole
sudo curl -o /var/www/html/pihole/index.html https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/index.html
sudo wget https://github.com/jacobsalmela/AdminLTE/archive/master.zip -O /var/www/master.zip
sudo unzip -o /var/www/master.zip -d /var/www/html/
sudo mv /var/www/html/AdminLTE-master /var/www/html/admin
sudo rm /var/www/master.zip 2>/dev/null
sudo touch /var/log/pihole.log
sudo chmod 644 /var/log/pihole.log
sudo chown dnsmasq:root /var/log/pihole.log
sudo curl -o /usr/local/bin/gravity.sh https://raw.githubusercontent.com/jacobsalmela/pi-hole/installation/gravity.sh
sudo curl -o /usr/local/bin/chronometer.sh https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/Scripts/chronometer.sh
sudo curl -o /usr/local/bin/whitelist.sh https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/Scripts/whitelist.sh
sudo curl -o /usr/local/bin/piholeLogFlush.sh https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/Scripts/piholeLogFlush.sh
sudo chmod 755 /usr/local/bin/gravity.sh
sudo chmod 755 /usr/local/bin/chronometer.sh
sudo chmod 755 /usr/local/bin/whitelist.sh
sudo /usr/local/bin/gravity.sh
sudo service networking restart
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
	# If only IPv6 is selected, exit because it is not supported yet
	if [[ "$useIPv6" = true ]] && [[ "$useIPv4" = false ]];then
		useIPv6dialog
		exit
	else
		useIPv6dialog
	fi
else
	useIPv6=false
	echo "IPv6 will NOT be used.  Consider a donation at pi-hole.net/donate"
fi

# Install and log everything to a file
installPihole | tee $tmpLog

# Move the log file into /etc/pihole for storage
sudo mv $tmpLog $instalLogLoc

whiptail --msgbox --backtitle "Make it so." --title "Installation Complete!" "Configure your devices to use the Pi-hole as their DNS server using this IP: $IPv4addr.

If you didn't use DHCP settings as your new static address, the Pi will restart after this dialog.  If you are using SSH, you may need to reconnect using the IP address above.

The install log is in /etc/phole." $r $c

# If a custom address was set, restart
if [[ "$rebootNeeded" = true ]];then
	# Restart to apply the new static IP address
	sudo reboot
else
	# If not, just start the services since the address will stay the same
	sudo service dnsmasq start
	sudo service lighttpd start
fi
