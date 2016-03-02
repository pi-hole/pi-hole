#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Completely uninstalls Pi-hole
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

# Check if root, and if not then rerun with sudo.
echo ":::"
if [[ $EUID -eq 0 ]];then
	echo "::: You are root."
	# Older versions of Pi-hole set $SUDO="sudo" and prefixed commands with it,
	# rather than rerunning as sudo. Just in case it turns up by accident, 
	# explicitly set the $SUDO variable to an empty string.
	SUDO=""
else
	echo "::: sudo will be used."
	# Check if it is actually installed
	# If it isn't, exit because the install cannot complete
	if [[ $(dpkg-query -s sudo) ]];then
		echo "::: Running sudo $0 $@"
		sudo "$0" "$@"
		exit $?
	else
		echo "::: Please install sudo or run this script as root."
	exit 1
	fi
fi


######### SCRIPT ###########
apt-get -y remove --purge dnsutils bc toilet
apt-get -y remove --purge dnsmasq
apt-get -y remove --purge lighttpd php5-common php5-cgi php5

# Only web directories/files that are created by pihole should be removed.
echo "Removing the Pi-hole Web server files..."
rm -rf /var/www/html/admin
rm -rf /var/www/html/pihole
rm /var/www/html/index.lighttpd.orig

# If the web directory is empty after removing these files, then the parent html folder can be removed.
if [[ ! "$(ls -A /var/www/html)" ]]; then
    rm -rf /var/www/html
fi

echo "Removing dnsmasq config files..."
rm /etc/dnsmasq.conf /etc/dnsmasq.conf.orig

# Attempt to preserve backwards compatibility with older versions
# to guarantee no additional changes were made to /etc/crontab after
# the installation of pihole, /etc/crontab.pihole should be permanently
# preserved.
if [[ -f /etc/crontab.orig ]]; then
  echo "Initial Pi-hole cron detected.  Restoring the default system cron..."
	mv /etc/crontab /etc/crontab.pihole
	mv /etc/crontab.orig /etc/crontab
	service cron restart
fi

# Attempt to preserve backwards compatibility with older versions
if [[ -f /etc/cron.d/pihole ]];then
  echo "Removing cron.d/pihole..."
	rm /etc/cron.d/pihole
fi

echo "Removing config files and scripts..."
rm /etc/dnsmasq.conf
rm /etc/sudoers.d/pihole
rm -rf /etc/lighttpd/
rm /var/log/pihole.log
rm /usr/local/bin/gravity.sh
rm /usr/local/bin/chronometer.sh
rm /usr/local/bin/whitelist.sh
rm /usr/local/bin/piholeReloadServices.sh
rm /usr/local/bin/piholeSetPermissions.sh
rm /usr/local/bin/piholeLogFlush.sh
rm /usr/local/bin/updateDashboard.sh
rm -rf /etc/pihole/
