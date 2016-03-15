#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Blacklists domains
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
if [ ! -f /etc/pihole/pihole.var ]; then
	curl -o $HOME/piholeInstall/pihole.vars https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/automated%20install/pihole.vars
	source $HOME/piholeInstall/pihole.var
else
	source /etc/pihole/pihole.var
fi

if [ ! -f /etc/pihole/pihole.funcs ]; then
	curl -o $HOME/piholeInstall/pihole.funcs https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/automated%20install/pihole.funcs
	source $HOME/piholeInstall/pihole.funcs
else
	source /etc/pihole/pihole.funcs
fi

RootCheck

installPihole | tee $tmpLog

# Move the log file into /etc/pihole for storage
$SUDO mv $tmpLog $instalLogLoc

# Start services
$SUDO service dnsmasq start
$SUDO service lighttpd start