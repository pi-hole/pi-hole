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
instalLogLoc=/etc/pihole/install.log

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
#IPv6addr=$(ip addr show | awk '/scope\ global/ && /ff:fe/ {print $2}' | cut -d'/' -f1)

ethernetDevice="eth0"
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

set_static_ip()
{
# Append these lines to /etc/dhcpcd.conf to enable a static IP
echo "interface $ethernetDevice
static ip_address=$IPv4addr/24
static routers=$IPv4gw
static domain_name_servers=$IPv4gw" | sudo tee -a $dhcpcdFile >/dev/null
}

######## SCRIPT ############
# Just back up the original Pi-hole right away since it won't take long and it gets it out of the way
backupLegacyPihole

# Display the welcome dialog
whiptail --msgbox --backtitle "Welcome" --title "Pi-hole automated installer" "This installer will transform your Raspberry Pi into a network-wide ad blocker!" $r $c

# Explain the need for a static address
whiptail --msgbox --backtitle "Initating network interface" --title "Static IP Needed" "The Pi-hole is a SERVER so it needs a STATIC IP ADDRESS to function properly.

In the next section, you can choose to use your current network settings (DHCP) or to manually edit them." $r $c

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
# Set the static address
set_static_ip

# These are the commands to actually install the Pi-hole
# This is pretty ugly, but it works to present a nice front-end
# http://stackoverflow.com/questions/29161323/how-to-keep-associative-array-order-in-bash
# Maybe it would be better to just show the command output instead of the progress bar
declare -A commands;      declare -a echoes;
commands["Updating"]="sudo apt-get update"; echoes+=( "Updating" )
commands["Upgrading"]="sudo apt-get -y upgrade"; echoes+=( "Upgrading" )
commands["Installing chronomoter tools"]="sudo apt-get -y install dnsutils bc toilet"; echoes+=( "Installing chronomoter tools" )
commands["Installing a DNS server"]="sudo apt-get -y install dnsmasq"; echoes+=( "Installing a DNS server" )
commands["Instaling a Web server and PHP"]="sudo apt-get -y install lighttpd php5-common php5-cgi php5"; echoes+=( "Instaling a Web server and PHP" )
commands["Making an HTML folder"]="sudo mkdir /var/www/html"; echoes+=( "Making an HTML folder" )
commands["chowning the Web server"]="sudo chown www-data:www-data /var/www/html"; echoes+=( "chowning the Web server" )
commands["chmodding the Web server"]="sudo chmod 775 /var/www/html"; echoes+=( "chmodding the Web server" )
commands["Giving pi access to the Web server"]="sudo usermod -a -G www-data pi"; echoes+=( "Giving pi access to the Web server" )
commands["Stopping dnsmasq to modify it"]="sudo service dnsmasq stop"; echoes+=( "Stopping dnsmasq to modify it" )
commands["Stopping lighttpd to modify it"]="sudo service lighttpd stop"; echoes+=( "Stopping lighttpd to modify it" )
commands["Backing up the dnsmasq config file"]="sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig"; echoes+=( "Backing up the dnsmasq config file" )
commands["Backing up the lighttpd config file"]="sudo mv /etc/lighttpd/lighttpd.conf /etc/lighttpd/lighttpd.conf.orig"; echoes+=( "Backing up the lighttpd config file" )
commands["Backing up the default Web page"]="sudo mv /var/www/html/index.lighttpd.html /var/www/html/index.lighttpd.orig"; echoes+=( "Backing up the default Web page" )
commands["Installing the dnsmasq config file"]="sudo curl -o /etc/dnsmasq.conf https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/dnsmasq.conf"; echoes+=( "Installing the dnsmasq config file" )
commands["Installing the lighttpd config file"]="sudo curl -o /etc/lighttpd/lighttpd.conf https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/lighttpd.conf"; echoes+=( "Installing the lighttpd config file" )
commands["Enabling PHP"]="sudo lighty-enable-mod fastcgi fastcgi-php"; echoes+=( "Enabling PHP" )
commands["Making a directory for the Web interface"]="sudo mkdir /var/www/html/pihole"; echoes+=( "Making a directory for the Web interface" )
commands["Installing a blank HTML page to take place of ads"]="sudo curl -o /var/www/html/pihole/index.html https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/index.html"; echoes+=( "Installing a blank HTML page to take place of ads" )
commands["Downloading the Pi-hole dashboard"]="sudo wget https://github.com/jacobsalmela/AdminLTE/archive/master.zip -O /var/www/master.zip"; echoes+=( "Downloading the Pi-hole dashboard" )
commands["Unpacking the dashboard"]="sudo unzip /var/www/master.zip -d /var/www/html/"; echoes+=( "Unpacking the dashboard" )
commands["Renaming the dashboard"]="sudo mv /var/www/html/AdminLTE-master /var/www/html/admin"; echoes+=( "Renaming the dashboard" )
commands["Cleaning up the dashboard temp files"]="sudo rm /var/www/master.zip 2>/dev/null"; echoes+=( "Cleaning up the dashboard temp files" )
commands["Creating a log file for the Pi-hole"]="sudo touch /var/log/pihole.log"; echoes+=( "Creating a log file for the Pi-hole" )
commands["chmodding the log file"]="sudo chmod 644 /var/log/pihole.log"; echoes+=( "chmodding the log file" )
commands["chowning the log file so stats can be displayed"]="sudo chown dnsmasq:root /var/log/pihole.log"; echoes+=( "chowning the log file so stats can be displayed" )
commands["Initating sub-space transport of gravity"]="sudo curl -o /usr/local/bin/gravity.sh https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/gravity.sh"; echoes+=( "Initating sub-space transport of gravity" )
commands["Initating sub-space transport of chronometer"]="sudo curl -o /usr/local/bin/chronometer.sh https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/Scripts/chronometer.sh"; echoes+=( "Initating sub-space transport of chronometer" )
commands["chmodding gravity"]="sudo chmod 755 /usr/local/bin/gravity.sh"; echoes+=( "chmodding gravity" )
commands["chmodding the chronometer"]="sudo chmod 755 /usr/local/bin/chronometer.sh"; echoes+=( "chmodding the chronometer" )
commands["Entering the event horizion"]="sudo /usr/local/bin/gravity.sh"; echoes+=( "Entering the event horizion" )
commands["Rebooting"]="sudo reboot"; echoes+=( "Rebooting" )

# Everything in the parentheses is part of displaying the progress bar
(
# Get total number of commands to be run from the array
n=${#commands[*]};
# Set counter to increase every time a loop completes
i=0

# For each item in the array
for k in "${!echoes[@]}"
do

# Calculate the overall progress
percent=$(( 100*(++i)/n ))

# Update dialog box using the value of each key in the array
# Show the percentage and the echo messages from the array
cat <<EOF
XXX
$percent
Step $i of $n: ${echoes[$k]}
XXX
EOF

# Execute the command in the background (hidden from the user, not actually a background process)
${commands[${echoes[$k]}]} > $instalLogLoc 2>&1
done

# As the loop is progressing, the output is sent to whiptail to be displayed to the user
) |
whiptail --title "Opening your Pi-hole..." --gauge "Please wait..." $r $c 0
