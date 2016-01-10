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
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: You must run this script as a root user" 
   exit 1
fi

######### SCRIPT ###########
apt-get -y remove --purge dnsutils bc toilet
apt-get -y remove --purge dnsmasq
apt-get -y remove --purge lighttpd php5-common php5-cgi php5
rm -rf /var/www/html
rm /etc/dnsmasq.conf /etc/dnsmasq.conf.orig

# attempt to preserve backwards compatibility with older versions
# to gaurentee no additional changes were made to /etc/crontab after
# the installation of pihole, /etc/crontab.pihole should be permanently
# preserved.
# @TODO: debugging statement alerting user of this.
if [ -f /etc/crontab.orig ]; then
	mv /etc/crontab /etc/crontab.pihole
	mv /etc/crontab.orig /etc/crontab
	service cron restart
fi

# attempt to preserve backwards compatibility with older versions
if [ -f /etc/cron.d/pihole ]; then
	rm /etc/cron.d/pihole
fi

rm /etc/dnsmasq.conf
rm -rf /etc/lighttpd/
rm /var/log/pihole.log
rm /usr/local/bin/gravity.sh
rm /usr/local/bin/chronometer.sh
rm /usr/local/bin/whitelist.sh
rm /usr/local/bin/piholeLogFlush.sh
rm -rf /etc/pihole/
