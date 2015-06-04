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
'http://adblock.gjtech.net/?format=unix-hosts'
'http://someonewhocares.org/hosts/hosts'
'http://adblock.mahakala.is/')

# Variables for various stages of downloading and formatting the list
origin=/run/shm
piholeDir=/etc/pihole
justDomainsExtension=domains
matter=pihole.0.matter.txt
andLight=pihole.1.andLight.txt
supernova=pihole.2.supernova.txt
eventHorizon=pihole.3.eventHorizon.txt
accretionDisc=pihole.4.accretionDisc.txt
eyeOfTheNeedle=pihole.5.wormhole.txt
adList=/etc/dnsmasq.d/adList.conf
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
	
	# Check if the site is down and skip it if it is
	httpResponse=$(curl -s -o /dev/null -w "%{http_code}" "${sources[$i]}")
	case "$httpResponse" in
		200) echo "$httpResponse response from $domain";;
		4[0-9][0-9]) echo "$httpResponse response from $domain: list will NOT be downloaded.";continue;;
		5[0-9][0-9]) echo "$httpResponse response from $domain: list will NOT be downloaded.";continue;;
		*) echo "$httpResponse response from $domain";;
	esac
	
	# Download file only if newer
	data=$(curl -s -z $saveLocation."$justDomainsExtension" -A "Mozilla/10.0" "${sources[$i]}")
	if [ -n "$data" ];then
        echo "Getting $domain list..."
        # Parse out just the domains
	    # If field 1 has a "#" and field one has a "/" and field 2 has a "#" and if the line ($0) is not empty and field 2 is not empty, print the 2nd field, which should be just the domain name
		# Remove Windows-style newlines
	    # Redirect output to file 
        echo "$data" | awk '{if ($1 !~ "#" && $1 !~ "/" && $2 !~ "#" && $2 !~ "/" && $0 != "^$" && $2 != "") { print $2}}' | sed $'s/\r$//' > $saveLocation."$justDomainsExtension" 
	    echo "	$(cat $saveLocation.$justDomainsExtension | wc -l | sed 's/^[ \t]*//') domains found."
    else
        echo "Skipping $domain list because it does not have any new entries..."
    fi
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
	echo -n "" > $origin/$supernova && grep '\.' $origin/$andLight >> $origin/$supernova
	# Remove newlines, blank lines, sort, and remove duplicates
	cat $origin/$supernova | sed $'s/\r$//' | sed '/^$/d' | sort | uniq > $origin/$eventHorizon
	numberOf=$(cat $origin/$eventHorizon | wc -l | sed 's/^[ \t]*//')
	echo "$numberOf unique domains trapped in the event horizon."
	# Format domain list as address=/example.com/127.0.0.1
	echo "** Formatting domains into a dnsmasq file..."
	cat $origin/$eventHorizon | awk -v "IP=$piholeIP" '{sub(/\r$/,""); print "address=/"$0"/"IP}' > $origin/$accretionDisc
	sudo cp $origin/$accretionDisc $adList
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
