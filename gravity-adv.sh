#!/bin/bash
# Address to send ads to (the RPi)
piholeIP="127.0.0.1"
# Optionally, uncomment to automatically detect the local IP address.
#piholeIP=$(hostname -I)

# Ad-list sources--one per line in single quotes
sources=('http://pgl.yoyo.org/adservers/serverlist.php?='
'http://winhelp2002.mvps.org/hosts.txt'
'https://adaway.org/hosts.txt'
'http://hosts-file.net/.%5Cad_servers.txt'
'http://www.malwaredomainlist.com/hostslist/hosts.txt'
'http://someonewhocares.org/hosts/hosts'
'http://adblock.gjtech.net/?format=unix-hosts'
'http://adblock.mahakala.is/')

# Variables for various stages of downloading and formatting the list
origin=/tmp
piholeDir=/etc/pihole
justDomainsExtension=domains
matter=pihole.0.matter.txt
andLight=pihole.1.andLight.txt
eventHorizion=pihole.2.eventHorizon.txt
accretionDisc=/etc/dnsmasq.d/adList.conf
blacklist=$piholeDir/blacklist.txt
whitelist=$piholeDir/whitelist.txt

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
	
	# Use a case statement for the domains that need extra options with the curl command.  If it doesn't need anything special, just download and format it.
	case "$domain" in
	
	"pgl.yoyo.org")
		echo "Getting $domain list...";
		curl -s -o "$saveLocation" -d mimetype=plaintext -d hostformat=unixhosts "${sources[$i]}";
		cat "$saveLocation" > $saveLocation.$justDomainsExtension;;
	
	"adblock.mahakala.is")
		echo "Getting $domain list...";
		curl -o "$saveLocation" -A 'Mozilla/5.0 (X11; Linux x86_64; rv:30.0) Gecko/20100101 Firefox/30.0' -e http://forum.xda-developers.com/ "${sources[$i]}";
		cat "$saveLocation" | awk '{if ($1 !~ "#" && $1 !~ "/" && $2 !~ "#" && $2 !~ "/" && $0 != "^$" && $2 != "") { print $2}}' > $saveLocation."$justDomainsExtension";;
		
	*) # Runs if the domain doesn't need a specialized curl command
		echo "Getting $domain list...";
		curl -s -o "$saveLocation" "${sources[$i]}";
		# Remove comments and blank lines.  Print on the domain (the $2nd field)
		cat "$saveLocation" | awk '{if ($1 !~ "#" && $1 !~ "/" && $2 !~ "#" && $2 !~ "/" && $0 != "^$" && $2 != "") { print $2}}' > $saveLocation."$justDomainsExtension";;
	
	esac 
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
	cat $origin/$andLight | awk -F. '{for (i=NF; i>1; --i) printf "%s.",$i;print $1}' | sort -t'.' -k1,2 | awk -F. '{for (i=NF; i>1; --i) printf "%s.",$i;print $1}' | uniq > $origin/$eventHorizion
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
	cat $origin/$matter | grep -vwf $whitelist > $origin/$andLight
	gravity_advanced
	
else
	cat $origin/$matter > $origin/$andLight
	gravity_advanced
fi