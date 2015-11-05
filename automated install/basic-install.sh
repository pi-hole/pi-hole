#!/bin/bash
# Pi-hole automated install
# Raspberry Pi Ad-blocker
#
# Install with this command (from the Pi):
#
# curl -s "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/automated%20install/basic-install.sh" | bash
#
# Or run the commands below in order

clear
echo "  _____ _        _           _      "
echo " |  __ (_)      | |         | |     "
echo " | |__) |   __  | |__   ___ | | ___ "
echo " |  ___/ | |__| | '_ \ / _ \| |/ _ \ "
echo " | |   | |      | | | | (_) | |  __/ "
echo " |_|   |_|      |_| |_|\___/|_|\___| "
echo "                                    "
echo "      Raspberry Pi Ad-blocker       "
echo "									  "
echo "Set a static IP before running this!"
echo "			             			  "
echo "	    Press Enter when ready        "
echo "									  "
read

#Checks if the script is being run as root and sets sudo accordingly
SUDO=''
if (( $EUID !=0 )); then SUDO='sudo'
fi

if [[ -f /etc/dnsmasq.d/adList.conf ]];then
	echo "Original Pi-hole detected.  Initiating sub space transport..."
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

echo "Updating the Pi..."
$SUDO apt-get update
$SUDO apt-get -y upgrade

echo "Installing tools..."
$SUDO apt-get -y install dnsutils
$SUDO apt-get -y install bc
$SUDO apt-get -y install toilet

echo "Installing DNS..."
$SUDO apt-get -y install dnsmasq
$SUDO update-rc.d dnsmasq enable

echo "Installing a Web server"
$SUDO apt-get -y install lighttpd php5-common php5-cgi php5
$SUDO mkdir /var/www/html
$SUDO chown www-data:www-data /var/www/html
$SUDO chmod 775 /var/www/html
$SUDO usermod -a -G www-data pi

echo "Stopping services to modify them..."
$SUDO service dnsmasq stop
$SUDO service lighttpd stop

echo "Backing up original config files and downloading Pi-hole ones..."
$SUDO mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
$SUDO mv /etc/lighttpd/lighttpd.conf /etc/lighttpd/lighttpd.conf.orig
$SUDO mv /var/www/html/index.lighttpd.html /var/www/html/index.lighttpd.orig
$SUDO curl -o /etc/dnsmasq.conf "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/dnsmasq.conf"
$SUDO curl -o /etc/lighttpd/lighttpd.conf "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/lighttpd.conf"
$SUDO lighty-enable-mod fastcgi fastcgi-php
$SUDO mkdir /var/www/html/pihole
$SUDO curl -o /var/www/html/pihole/index.html "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/index.html"

echo "Installing the Web interface..."
$SUDO wget https://github.com/jacobsalmela/AdminLTE/archive/master.zip -O /var/www/master.zip
$SUDO unzip /var/www/master.zip -d /var/www/html/
$SUDO mv /var/www/html/AdminLTE-master /var/www/html/admin
$SUDO rm /var/www/master.zip 2>/dev/null
$SUDO touch /var/log/pihole.log
$SUDO chmod 644 /var/log/pihole.log
$SUDO chown dnsmasq:root /var/log/pihole.log

echo "Locating the Pi-hole..."
$SUDO curl -o /usr/local/bin/gravity.sh "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/gravity.sh"
$SUDO curl -o /usr/local/bin/chronometer.sh "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/Scripts/chronometer.sh"
$SUDO chmod 755 /usr/local/bin/gravity.sh
$SUDO chmod 755 /usr/local/bin/chronometer.sh

echo "Entering the event horizon..."
$SUDO /usr/local/bin/gravity.sh

echo "Restarting..."
$SUDO reboot
