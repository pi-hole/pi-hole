#!/bin/bash
# Address to send ads to (the RPi)
piholeIP="127.0.0.1"
# Optionally, uncomment to automatically detect the local IP address.
#piholeIP=$(hostname -I)

# Ad-list sources--one per line in single quotes
sources=('http://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&mimetype=plaintext'
'http://winhelp2002.mvps.org/hosts.txt'
'https://adaway.org/hosts.txt'
'http://hosts-file.net/.%5Cad_servers.txt'
'http://www.malwaredomainlist.com/hostslist/hosts.txt'
'http://someonewhocares.org/hosts/hosts'
'http://adblock.gjtech.net/?format=unix-hosts'
'http://adblock.mahakala.is/'
'http://cdn.files.trjlive.com/hosts/hosts-v8.txt')

# Variables for various stages of downloading and formatting the list
origin=/run/shm
piholeDir=/etc/pihole
justDomainsExtension=domains
matter=pihole.0.matter.txt
andLight=pihole.1.andLight.txt
supernova=pihole.2.supernova.txt
eventHorizion=pihole.3.eventHorizon.txt
accretionDisc=/etc/dnsmasq.d/adList.conf
blacklist=$piholeDir/blacklist.txt
latentBlacklist=$origin/latentBlacklist.txt
whitelist=$piholeDir/whitelist.txt
latentWhitelist=$origin/latentWhitelist.txt

# Create the Pi-Hole directory if it doesn't exist
if [[ -d $piholeDir ]];then
	:
else
	echo "** Forming Pi-hole directory..."
	sudo mkdir $piholeDir
fi

# Loop through domain list.  Download each one and remove commented lines (lines beginning with '# 'or '/') and blank lines
for ((i = 0; i < "${#sources[@]}"; i++))
do
	# Get just the domain from the URL
	domain=$(echo "${sources[$i]}" | cut -d'/' -f3)
	
	# Save the file as list.#.domain
	saveLocation=$origin/"list"."$i"."$domain"
		
	echo "Getting $domain list..."
	curl -s -o "$saveLocation" -A "Mozilla/10.0" "${sources[$i]}"
	# Parse out just the domains
	# If field 1 has a "#" and field one has a "/" and field 2 has a "#" and if the line ($0) is not empty and field 2 is not empty, print the 2nd field, which should be just the domain name
	cat "$saveLocation" | awk '{if ($1 !~ "#" && $1 !~ "/" && $2 !~ "#" && $2 !~ "/" && $0 != "^$" && $2 != "") { print $2}}' > $saveLocation."$justDomainsExtension" 
	echo "	$(cat $saveLocation.$justDomainsExtension | wc -l | sed 's/^[ \t]*//') domains found."
done

# Find all files with the .domains extension and compile them into one file
echo "Aggregating list of domains..."
find $origin/ -type f -name "*.$justDomainsExtension" -exec cat {} \; > $origin/$matter

# Append entries from the blacklist file if it exists
if [[ -f $blacklist ]];then
	numberOf=$(cat $blacklist | wc -l | sed 's/^[ \t]*//')
	echo "** Appending $numberOf blacklist entries..."
	cat $blacklist >> $origin/$matter
else
        :
fi

function gravity_advanced()
###########################
	{
	# Sort domains by TLD and remove duplicates
	numberOf=$(cat $origin/$andLight | wc -l | sed 's/^[ \t]*//')
	echo "$numberOf domains being pulled in by gravity..."	
	# Remove lines with no dots (i.e. localhost, localdomain, etc)
	echo -n "" > $origin/$supernova;for i in $origin/$andLight;do grep '\.' $i >> $origin/$supernova;done
	# Remove newlines, sort by TLD, remove duplicates
	cat $origin/$supernova | sed $'s/\r$//' | awk -F. '{for (i=NF; i>1; --i) printf "%s.",$i;print $1}' | sort -t'.' -k1,2 | awk -F. 'NR!=1&&substr($0,1,length(p))==p {next} {p=$0".";for (i=NF; i>1; --i) printf "%s.",$i;print $1}' | uniq > $origin/$eventHorizion
	numberOf=$(cat $origin/$eventHorizion | wc -l | sed 's/^[ \t]*//')
	echo "$numberOf unique domains trapped in the event horizon."
	# Format domain list as address=/example.com/127.0.0.1
	echo "** Formatting domains into a dnsmasq file..."
	cat $origin/$eventHorizion | awk -v "IP=$piholeIP" '{sub(/\r$/,""); print "address=/"$0"/"IP}' > $accretionDisc
	sudo service dnsmasq restart
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
	gravity_advanced
	
else
	cat $origin/$matter > $origin/$andLight
	gravity_advanced
fi