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
# Get the screen size in case we need a full-screen message and so we can display a dialog that is sized nicely
screenSize=$(stty -a | tr \; \\012 | egrep 'rows|columns' | cut '-d ' -f3)

# Find the rows and columns
rows=$(stty -a | tr \; \\012 | egrep 'rows' | cut -d' ' -f3)
columns=$(stty -a | tr \; \\012 | egrep 'columns' | cut -d' ' -f3)

# Divide by two so the dialogs take up half of the screen, which looks nice.
r=$(( rows / 2 ))
c=$(( columns / 2 ))

# Get the current network settings
IPv4addr=$(ip -4 addr show | awk '{match($0,/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/); ip = substr($0,RSTART,RLENGTH); print ip}' | sed '/^\s*$/d' | grep -v "127.0.0.1")
IPv4mask=$(ifconfig | awk -F':' '/inet addr/ && !/127.0.0.1/ {print $4}')
IPv4gw=$(ip route show | awk '/default\ via/ {print $3}')

# IPv6 support to be added later
IPv6addr=$(ip addr show | awk '/scope\ global/ && /ff:fe/ {print $2}' | cut -d'/' -f1)

####### FUCNTIONS ##########
backupLegacyPihole()
{
if [[ -f /etc/dnsmasq.d/adList.conf ]];then
	echo "Original Pi-hole detected.  Initiating sub space transport..."
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

######## SCRIPT ############
# Just back up the original Pi-hole right away since it won't take long and it gets it out of the way
backupLegacyPihole

# Display the welcome dialog
whiptail --msgbox --backtitle "Welcome..." --title "Pi-hole automated installer" "This installer will transform your Raspberry Pi into a network-wide ad blocker!" $r $c

# Explain the need for a static address
whiptail --msgbox --backtitle "Initating network interface..." --title "Static IP Needed" "The Pi-hole is a SERVER so it needs a STATIC IP ADDRESS to function properly.

In the next section, you can choose to use your current network settings (DHCP) or to manually edit them." $r $c

# Ask if the user wannts to use DHCP settings as their static IP
if (whiptail --title "Static IP Address" --yesno "Do you want to use your current network settings as a static address?

							IP address:    $IPv4addr
							Subnet mask:   $IPv4mask
							Gateway:       $IPv4gw" $r $c) then
	# If they choose yes, let the user know that the IP address will not be available via DHCP and may cause a conflict.
	whiptail --msgbox --backtitle "IP information..." --title "FYI: IP Conflict" "It is possible your router could still try to assign this IP to a device, which would cause a conflict.  But in most cases the router is smart enough to not do that.

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
	IPv4addr=$(whiptail --backtitle "Calibrating network interface..." --title "IPv4 address" --inputbox "Enter your desired IPv4 address" $r $c $IPv4addr 3>&1 1>&2 2>&3)
	if [[ $? = 0 ]];then
    	echo "Your static IPv4 address:    $IPv4addr"
		# Ask for the subnet mask
		IPv4mask=$(whiptail --backtitle "Calibrating network interface..." --title "IPv4 netmask" --inputbox "Enter your desired IPv4 subnet mask" $r $c $IPv4mask 3>&1 1>&2 2>&3)
		if [[ $? = 0 ]];then
				echo "Your static IPv4 netmask:    $IPv4mask"
				# Ask for the gateway
				IPv4gw=$(whiptail --backtitle "Calibrating network interface..." --title "IPv4 gateway (router)" --inputbox "Enter your desired IPv4 default gateway" $r $c $IPv4gw 3>&1 1>&2 2>&3)
				if [[ $? = 0 ]];then
						echo "Your static IPv4 gateway:    $IPv4gw"
						# Give the user a chance to review their settings before moving on
						if (whiptail --title "Static IP Address" --yesno "Are these settings correct?
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

# These are the commands to actually install the Pi-hole
# Create an associative array so we can display text to the user but run the associated command in the background.
declare -A cmdsAndEchoes=([sudo apt-get update]='Updating...'
[sudo apt-get -y upgrade]='Upgrading...'
[sudo apt-get -y install dnsutils bc toilet]='Installing chronomoter tools...'
[sudo apt-get -y install dnsmasq]='Installing a DNS server...'
[sudo apt-get -y install lighttpd php5-common php5-cgi php5]='Instaling a Web server and PHP...'
[sudo mkdir /var/www/html]='Making an HTML folder...'
[sudo chown www-data:www-data /var/www/html]='Setting permissions for the Web server...'
[sudo chmod 775 /var/www/html]='Setting permissions for the Web server...'
[sudo usermod -a -G www-data pi]='Setting permissions for the Web server...'
[sudo service dnsmasq stop]='Stopping dnsmasq to modify it...'
[sudo service lighttpd stop]='Stopping lighttpd to modify it...'
[sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig]='Backing up the dnsmasq config file...'
[sudo mv /etc/lighttpd/lighttpd.conf /etc/lighttpd/lighttpd.conf.orig]='Backing up the lighttpd config file...'
[sudo mv /var/www/html/index.lighttpd.html /var/www/html/index.lighttpd.orig]='Backing up the default Web page...'
[sudo curl -o /etc/dnsmasq.conf https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/dnsmasq.conf]='Installing the dnsmasq config file...'
[sudo curl -o /etc/lighttpd/lighttpd.conf https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/lighttpd.conf]='Installing the lighttpd config file...'
[sudo lighty-enable-mod fastcgi fastcgi-php]='Enabling PHP...'
[sudo mkdir /var/www/html/pihole]='Making a directory for the Web interface...'
[sudo curl -o /var/www/html/pihole/index.html https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/index.html]='Installing a blank HTML page to take place of ads...'
[sudo wget https://github.com/jacobsalmela/AdminLTE/archive/master.zip -O /var/www/master.zip]='Downloading the Pi-hole dashboard...'
[sudo unzip /var/www/master.zip -d /var/www/html/]='Unpacking the dashboard...'
[sudo mv /var/www/html/AdminLTE-master /var/www/html/admin]='Renaming the dashboard...'
[sudo rm /var/www/master.zip 2>/dev/null]='Cleaning up the dashboard temp files...'
[sudo touch /var/log/pihole.log]='Creating a log file for the Pi-hole...'
[sudo chmod 644 /var/log/pihole.log]='Making sure the log is readable...'
[sudo chown dnsmasq:root /var/log/pihole.log]='Letting dnsmasq see the log file so stats can be displayed...'
[sudo curl -o /usr/local/bin/gravity.sh "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/gravity.sh"]='Initating sub-space transport...'
[sudo curl -o /usr/local/bin/chronometer.sh "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/Scripts/chronometer.sh"]='Initating sub-space transport...'
[sudo chmod 755 /usr/local/bin/gravity.sh]='Making the scripts executable...'
[sudo chmod 755 /usr/local/bin/chronometer.sh]='Making the scripts executable...'
[sudo /usr/local/bin/gravity.sh]='Entering the event horizion...'
[sudo reboot]='Restarting...')

# Everything in the parentheses is part of displaying the progress bar
(
# Get total number of commands to be run from the array
n=${#cmdsAndEchoes[*]};

# Set counter to increase every time a loop completes
i=0

# For each key in the array
for key in "${!cmdsAndEchoes[@]}"
do

# Calculate the overall progress
percent=$(( 100*(++i)/n ))

# Update dialog box using the value of each key in the array
# Show the percentage and the echo messages from the array
cat <<EOF
XXX
$percent
${cmdsAndEchoes[$key]}
XXX
EOF
# Execute the command in the background (hidden from the user, not actually a background process)
$key
done
# As the loop is progressing, the output is sent to whiptail to be displayed to the user
) |
whiptail --title "Opening your Pi-hole..." --gauge "Please wait..." $r $c 0
