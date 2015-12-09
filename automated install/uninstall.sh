#!/usr/bin/env bash
# Completely uninstalls the Pi-hole
# (c) 2015 by Jacob Salmela
# This file is part of Pi-hole.
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.


######### SCRIPT ###########
sudo apt-get -y remove --purge dnsutils bc toilet
sudo apt-get -y remove --purge dnsmasq
sudo apt-get -y remove --purge lighttpd php5-common php5-cgi php5
sudo rm -rf /var/www/html
sudo rm /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
sudo rm /etc/crontab
sudo mv /etc/crontab.orig /etc/crontab
sudo rm /etc/dnsmasq.conf
sudo rm -rf /etc/lighttpd/
sudo rm /var/log/pihole.log
sudo rm /usr/local/bin/gravity.sh
sudo rm /usr/local/bin/chronometer.sh
sudo rm /usr/local/bin/whitelist.sh
sudo rm /usr/local/bin/piholeLogFlush.sh
sudo rm -rf /etc/pihole/
