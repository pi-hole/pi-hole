#!/bin/bash
# Pi-hole automated install
# Raspberry Pi Ad-blocker
#
# Install with this command (from the Pi):
#
# curl -s "" | bash
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
echo "         Automated install          "
echo "			  --Basic-- 			  "
echo "									  "
echo "									  "
echo " Press enter to continue..."
read userReady

# Update the Pi
sudo apt-get update
sudo apt-get -y upgrade

# Install DNS
sudo apt-get -y install dnsutils dnsmasq

# Install lighttpd Web server
sudo apt-get -y install lighttpd
sudo chown www-data:www-data /var/www
sudo chmod 775 /var/www
sudo usermod -a -G www-data pi

# Install minidlna
#sudo apt-get -y install minidlna

# Stop services before modifying settings
sudo service dnsmasq stop
sudo service lighttpd stop
#sudo service minidlna stop

# Backup original config files and download new ones
#sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
sudo mv /etc/lighttpd/lighttpd.conf /etc/lighttpd/lighttpd.conf.orig
sudo mv /var/www/index.lighttpd.html /var/www/index.lighttpd.orig
sudo curl -o /etc/dnsmasq.conf.pihole "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/dnsmasq.conf"
sudo curl -o /etc/lighttpd/lighttpd.conf "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/lighttpd.conf"
sudo mkdir /var/www/pihole
sudo curl -o /var/www/pihole/index.html "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/index.html"

sudo curl -o /tmp/piholedns.sh "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/advanced/enable-dns.sh"
sudo chmod 755 /tmp/piholedns.sh

sudo curl -o /usr/local/bin/gravity.sh "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/gravity.sh"
sudo chmod 755 /usr/local/bin/gravity.sh
sudo /usr/local/bin/gravity.sh

# Open your Pi-hole
sudo service lighttpd start
#sudo service minidlna start
sudo /tmp/piholedns.sh