#!/bin/bash
# Address to send ads to (the RPi)
piholeIP="127.0.0.1"
# Optionally, uncomment to automatically detect the local IP address.
#piholeIP=$(hostname -I)

# Variables for various stages of downloading and formatting the list
origin=~/Desktop/pihole
piholeDir=/etc/pihole
justDomainsExtension=domains
matter=pihole.0.matter.txt
andLight=pihole.1.andLight.txt
supernova=pihole.2.supernova.txt
eventHorizion=pihole.3.eventHorizon.txt
eyeOfTheNeedle=pihole.4.wormhole.txt
accretionDisc=/etc/dnsmasq.d/adList.conf
blacklist=$piholeDir/blacklist.txt
latentBlacklist=$origin/latentBlacklist.txt
whitelist=$piholeDir/whitelist.txt
latentWhitelist=$origin/latentWhitelist.txt
gravity=/usr/local/bin/gravity.sh



function gravity_advanced()
###########################
	{
	if [[ -f $origin/$eventHorizion ]];then
		echo -e "\n\nWormhole navigation requires thrusters only. Let this run overnight or in the background."
		echo -e "Travelling through removes domains that no longer exist."
		echo -e "\n\n\n\t*** Press Return to enter the wormhole or press Ctrl+Z to return to starbase."
		read
	
		numberOf=$(cat $origin/$eventHorizion | wc -l | sed 's/^[ \t]*//')
		echo "$numberOf unique domains exist before entering the wormhole."
		rm -f $origin/$eyeOfTheNeedle >/dev/null
		while read shuttle;do
			dig "$shuttle" | grep 'ANSWER SECTION' >/dev/null
			if [[ $? = 0 ]];then
				echo "Checking if $shuttle is operational..."
				echo "$shuttle" >> $origin/$eyeOfTheNeedle
			else
				:
			fi 
		done < $origin/$eventHorizion
		numberRemoved=$(cat $origin/$eyeOfTheNeedle | wc -l | sed 's/^[ \t]*//')
		removed=$(($numberOf - $numberRemoved))
		echo -e "\t*** $removed domains were removed by travelling through the wormhole."
		echo -e "\t*** $numberRemoved unique and active domains can now be blocked."
		
		# Format domain list as address=/example.com/127.0.0.1
		echo "** Formatting domains into a dnsmasq file..."
		cat $origin/$eyeOfTheNeedle | awk -v "IP=$piholeIP" '{sub(/\r$/,""); print "address=/"$0"/"IP}' > $accretionDisc
		sudo service dnsmasq restart
	
	else
		echo "You need to run $gravity first."
		exit 1
	fi
	}
	
# Whitelist (if applicable) then remove duplicates and format for dnsmasq
if [[ -f $whitelist ]];then
	# Remove whitelist entries
	numberOf=$(cat $whitelist | wc -l | sed 's/^[ \t]*//')
	echo "** Whitelisting $numberOf domain(s)..."
	# Append a "$" to the end of each line so it can be parsed out with grep -w
	echo -n "^$" > $latentWhitelist
	awk -F '[# \t]' 'NF>0&&$1!="" {print $1"$"}' $whitelist > $latentWhitelist
	cat $origin/$matter | grep -vwf $latentWhitelist > $origin/$andLight
	clear
	gravity_advanced
	
else
	cat $origin/$matter > $origin/$andLight
	gravity_advanced
fi