#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Generates pihole_debug.log in /var/log/ to be used for troubleshooting.
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

# Nate Brandeburg
# nate@ubiquisoft.com
# 3/19/2016

######## GLOBAL VARS ########
DEBUG_LOG="/var/log/pihole_debug.log"

######## FIRST CHECK ########
# Must be root to debug
if [[ $EUID -eq 0 ]];then
	echo "::: You are root... Beginning debug!"
else
	echo "::: sudo will be used for debugging."
	# Check if sudo is actually installed
	if [[ $(dpkg-query -s sudo) ]];then
		export SUDO="sudo"
	else
		echo "::: Please install sudo or run this as root."
		exit 1
	fi
fi

# Ensure the file exists, create if not, clear if exists.
if [ ! -f "$DEBUG_LOG" ] 
then
	$SUDO touch $DEBUG_LOG
	$SUDO chmod 644 $DEBUG_LOG
	$SUDO chown "$USER":root $DEBUG_LOG
else 
	truncate -s 0 $DEBUG_LOG
fi

### Check Pi internet connections ###
# Log the IP addresses of this Pi
IPADDR=$(ifconfig | perl -nle 's/dr:(\S+)/print $1/e')
echo "Writing local IPs to debug log"
echo "IP Addresses of this Pi:" >> $DEBUG_LOG
echo "$IPADDR" >> $DEBUG_LOG
echo >> $DEBUG_LOG

# Check if we can connect to the local gateway
GATEWAY_CHECK=$(ping -q -w 1 -c 1 "$(ip r | grep default | cut -d ' ' -f 3)" > /dev/null && echo ok || echo error)
echo "Gateway check:" >> $DEBUG_LOG
echo "$GATEWAY_CHECK" >> $DEBUG_LOG
echo >> $DEBUG_LOG

echo "Writing dnsmasq.conf to debug log..."
echo "############### Dnsmasq ###############" >> $DEBUG_LOG
DNSMASQFILE="/etc/dnsmasq.conf"
if [ -e "$DNSMASQFILE" ]
then
	cat $DNSMASQFILE >> $DEBUG_LOG
	echo >> $DEBUG_LOG
else
	echo "No dnsmasq.conf file found!" >> $DEBUG_LOG
	echo "No dnsmasq.conf file found!"
fi

echo "Writing hosts file to debug log..."
echo "############### Hosts ###############" >> $DEBUG_LOG
HOSTSFILE="/etc/hosts"
if [ -e "$HOSTSFILE" ]
then
	cat "$HOSTSFILE" >> $DEBUG_LOG
	echo >> $DEBUG_LOG
else
	echo "No hosts file found!" >> $DEBUG_LOG
	echo "No hosts file found!"
fi

### PiHole application specific logging ###
# Write Pi-Hole logs to debug log
echo "Writing whitelist to debug log..."
echo "############### Whitelist ###############" >> $DEBUG_LOG
WHITELISTFILE="/etc/pihole/whitelist.txt"
if [ -e "$WHITELISTFILE" ]
then
	cat "$WHITELISTFILE" >> $DEBUG_LOG
	echo >> $DEBUG_LOG
else
	echo "No whitelist.txt file found!" >> $DEBUG_LOG
	echo "No whitelist.txt file found!"
fi

echo "Writing blacklist to debug log..."
echo "############### Blacklist ###############" >> $DEBUG_LOG
BLACKLISTFILE="/etc/pihole/blacklist.txt"
if [ -e "$BLACKLISTFILE" ]
then
	cat "$BLACKLISTFILE" >> $DEBUG_LOG
	echo >> $DEBUG_LOG
else
	echo "No blacklist.txt file found!" >> $DEBUG_LOG
	echo "No blacklist.txt file found!"
fi

echo "Writing adlists.list to debug log..."
echo "############### adlists.list ###############" >> $DEBUG_LOG
ADLISTSFILE="/etc/pihole/adlists.list"
if [ -e "$ADLISTSFILE" ]
then
	cat "$ADLISTSFILE" >> $DEBUG_LOG
	echo >> $DEBUG_LOG
else
	echo "No adlists.list file found!" >> $DEBUG_LOG
	echo "No adlists.list file found!"
fi


# Continuously append the pihole.log file to the pihole_debug.log file
function dumpPiHoleLog {
	trap '{ echo -e "\nFinishing debug write from interrupt... Quitting!" ; exit 1; }' INT
	echo -e "Writing current pihole traffic to debug log...\nTry loading any/all sites that you are having trouble with now... (Press ctrl+C to finish)"
	echo "############### pihole.log ###############" >> $DEBUG_LOG
	PIHOLELOG="/var/log/pihole.log"
	if [ -e "$PIHOLELOG" ]
	then
		while true; do
			tail -f "$PIHOLELOG" >> $DEBUG_LOG
			echo >> $DEBUG_LOG
		done
	else
		echo "No pihole.log file found!" >> $DEBUG_LOG
		echo "No pihole.log file found!"
	fi
}

function finalWrites {
	# Write the gravity.list after the user is finished capturing the pihole.log output
	echo "Writing gravity.list to debug log..."
	echo "############### gravity.list ###############" >> $DEBUG_LOG
	GRAVITYFILE="/etc/pihole/gravity.list"
	if [ -e "$GRAVITYFILE" ]
	then
		cat /etc/pihole/gravity.list >> $DEBUG_LOG
		echo >> $DEBUG_LOG
	else
		echo "No gravity.list file found!" >> $DEBUG_LOG
		echo "No gravity.list file found"
	fi
}
trap finalWrites EXIT

### Method calls for additinal logging ###
dumpPiHoleLog
