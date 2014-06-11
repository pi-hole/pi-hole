#!/bin/bash
# /usr/local/bin/gravity.sh

# URL to pull list of known ad servers from
adListURL="http://pgl.yoyo.org/adservers/serverlist.php?hostformat=dnsmasq&showintro=0&mimetype=plaintext"

# Address to send ads to
piholeIP="127.0.0.1"

# Where the list of ad servers are stored once downloaded
# Any file in /etc/dnsmasq.d is loaded automatically when the service starts
adFile="/etc/dnsmasq.d/adList.conf"

# The temporary file for holding
eventHorizion="/etc/dnsmasq.d/adList.conf.tmp"
 
# Parses out the default 127.0.0.1 address and replaces it with the IP where ads will be sent
curl $adListURL | sed "s/127\.0\.0\.1/$piholeIP/" > $eventHorizion

# If the temporary list of ad servers already exists (the eventHorizion)  
if [ -f "$eventHorizion" ];then
	# Then replace it as the new ad file	
	mv -f $eventHorizion $adFile
else
	echo "Error building the ad list, please try again."
	exit 1
fi
service dnsmasq restart
