#!/usr/bin/env bash
# Completely uninstalls the Pi-hole
# (c) 2015 by Jacob Salmela
# This file is part of Pi-hole.
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

# Must be root to uninstall
if [[ $EUID -eq 0 ]];then
	echo "You are root."
else
	echo "sudo will be used for the install."
	export SUDO="sudo"
fi


######### SCRIPT ###########
$SUDO apt-get -y remove --purge dnsutils bc toilet
$SUDO apt-get -y remove --purge dnsmasq
$SUDO apt-get -y remove --purge lighttpd php5-common php5-cgi php5

# Only web directories/files that are created by pihole should be removed.
echo "Removing the Pi-hole Web server files..."
$SUDO rm -rf /var/www/html/admin
$SUDO rm -rf /var/www/html/pihole
$SUDO rm /var/www/html/index.lighttpd.orig

# If the web directory is empty after removing these files, then the parent html folder can be removed.
if [[ ! "$(ls -A /var/www/html)" ]]; then
    $SUDO rm -rf /var/www/html
fi

echo "Removing dnsmasq config files..."
$SUDO rm /etc/dnsmasq.conf /etc/dnsmasq.conf.orig

# Attempt to preserve backwards compatibility with older versions
# to guarantee no additional changes were made to /etc/crontab after
# the installation of pihole, /etc/crontab.pihole should be permanently
# preserved.
if [[ -f /etc/crontab.orig ]]; then
  echo "Initial Pi-hole cron detected.  Restoring the default system cron..."
	$SUDO mv /etc/crontab /etc/crontab.pihole
	$SUDO mv /etc/crontab.orig /etc/crontab
	$SUDO service cron restart
fi

# Attempt to preserve backwards compatibility with older versions
if [[ -f /etc/cron.d/pihole ]];then
  echo "Removing cron.d/pihole..."
	$SUDO rm /etc/cron.d/pihole
fi

echo "Removing config files and scripts..."
$SUDO rm /etc/dnsmasq.conf
$SUDO rm -rf /etc/lighttpd/
$SUDO rm /var/log/pihole.log
$SUDO rm /usr/local/bin/gravity.sh
$SUDO rm /usr/local/bin/chronometer.sh
$SUDO rm /usr/local/bin/whitelist.sh
$SUDO rm /usr/local/bin/piholeLogFlush.sh
$SUDO rm -rf /etc/pihole/
