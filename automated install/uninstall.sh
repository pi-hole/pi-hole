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
rm /etc/crontab
mv /etc/crontab.orig /etc/crontab
rm /etc/dnsmasq.conf
rm -rf /etc/lighttpd/
rm /var/log/pihole.log
rm /usr/local/bin/gravity.sh
rm /usr/local/bin/chronometer.sh
rm /usr/local/bin/whitelist.sh
rm /usr/local/bin/piholeLogFlush.sh
rm -rf /etc/pihole/
