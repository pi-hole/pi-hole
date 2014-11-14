#!/bin/bash
# Block Hulu Plus ads using a Raspberry Pi

# Install with this command (from the Pi):
#
# curl -s https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/block%20hulu%20ads/setup.sh | bash
#
# Or run the commands below in order

# Update the Pi
sudo apt-get update
#sudo apt-get -y upgrade

# Install DNS
sudo apt-get -y install dnsutils dnsmasq
sudo service dnsmasq stop

# Install Web server
sudo apt-get -y install lighttpd
sudo service lighttpd stop

# Install streaming software
sudo apt-get -y install minidlna
sudo service minidlna stop

# Configure Web server
#sudo lighty-enable-mod fastcgi-php
sudo chown www-data:www-data /var/www
sudo chmod 775 /var/www
sudo usermod -a -G www-data pi
sudo mv /var/www/index.lighttpd.html /var/www/index.lighttpd.orig
sudo curl -o /var/www/index.html "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/block%20hulu%20ads/index.html"
sudo mv /etc/lighttpd/lighttpd.conf /etc/lighttpd/lighttpd.conf.orig
sudo curl -o /etc/lighttpd/lighttpd.conf "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/block%20hulu%20ads/lighttpd.conf"

# Configure streaming service
sudo mv /etc/minidlna.conf /etc/minidlna.conf.orig
sudo mkdir /var/lib/minidlna/videos/
sudo curl -o /etc/minidlna.conf "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/block%20hulu%20ads/minidlna.conf"
sudo service minidlna start
sudo curl -o /var/lib/minidlna/videos/pi-hole.mov "https://dl.dropboxusercontent.com/u/16366947/Documents/Videos/pi-hole.mov"
sudo service minidlna force-reload
tail /var/log/minidlna.log

# Configure DNS
sudo curl -o /etc/dnsmasq.conf.pihole "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/dnsmasq.conf"
sudo curl -o /tmp/piholedns.sh "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/block%20hulu%20ads/setup-resolv.sh"
sudo chmod 755 /tmp/piholedns.sh

# Download [advanced] ad-blocking script and then run it
# http://jacobsalmela.com/raspberry-pi-ad-blocker-advanced-setup/
sudo curl -o /usr/local/bin/gravity.sh "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/gravity-adv.sh"
sudo chmod 755 /usr/local/bin/gravity.sh
clear
echo ""
echo ""
echo ""
echo ""
echo "Go get some coffee--this will take a while"
echo ""
echo ""
echo ""
echo ""
sleep 5
sudo /usr/local/bin/gravity.sh
sudo service dnsmasq stop

# Restart everything to apply all the changes
sudo service lighttpd start
sudo service minidlna start
sudo /tmp/piholedns.sh