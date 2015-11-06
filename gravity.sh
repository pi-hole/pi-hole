#!/bin/bash
# http://pi-hole.net
# Compiles a list of ad-serving domains by downloading them from multiple sources

# This script should only be run after you have a static IP address set on the Pi
piholeIP=$(hostname -I)

# Ad-list sources--one per line in single quotes
sources=('https://adaway.org/hosts.txt'
'http://adblock.gjtech.net/?format=unix-hosts'
#'http://adblock.mahakala.is/'
'http://hosts-file.net/ad_servers.txt'
'http://www.malwaredomainlist.com/hostslist/hosts.txt'
'http://pgl.yoyo.org/adservers/serverlist.php?'
'http://someonewhocares.org/hosts/hosts'
'http://winhelp2002.mvps.org/hosts.txt')

# Variables for various stages of downloading and formatting the list
adList=/etc/pihole/gravity.list
origin=/etc/pihole
piholeDir=/etc/pihole
justDomainsExtension=domains
matter=pihole.0.matter.txt
andLight=pihole.1.andLight.txt
supernova=pihole.2.supernova.txt
eventHorizon=pihole.3.eventHorizon.txt
accretionDisc=pihole.4.accretionDisc.txt
eyeOfTheNeedle=pihole.5.wormhole.txt
blacklist=$piholeDir/blacklist.txt
whitelist=$piholeDir/whitelist.txt
latentWhitelist=$origin/latentWhitelist.txt

# After setting defaults, check if there's local overrides
if [[ -r $piholeDir/pihole.conf ]];then
    echo "** Local calibration requested..."
	. $piholeDir/pihole.conf
fi
echo "** Neutrino emissions detected..."

# Create the pihole resource directory if it doesn't exist.  Future files will be stored here
if [[ -d $piholeDir ]];then
	:
else
	echo "** Creating pihole directory..."
	sudo mkdir $piholeDir
fi

# Loop through domain list.  Download each one and remove commented lines (lines beginning with '# 'or '/') and blank lines
for ((i = 0; i < "${#sources[@]}"; i++))
do
	url=${sources[$i]}
	# Get just the domain from the URL
	domain=$(echo "$url" | cut -d'/' -f3)

	# Save the file as list.#.domain
	saveLocation=$origin/list.$i.$domain.$justDomainsExtension

	agent="Mozilla/10.0"

	echo -n "Getting $domain list... "

	# Use a case statement to download lists that need special cURL commands
	# to complete properly and reset the user agent when required
	case "$domain" in
		"adblock.mahakala.is")
			agent='Mozilla/5.0 (X11; Linux x86_64; rv:30.0) Gecko/20100101 Firefox/30.0'
			cmd="curl -e http://forum.xda-developers.com/"
			;;

		"pgl.yoyo.org")
			cmd="curl -d mimetype=plaintext -d hostformat=hosts"
			;;

		# Default is a simple curl request
		*) cmd="curl"
	esac

    echo "Narrowing the annular confinment beam..."
    # Create a tmp file so we don't have to store the (long!) lists in RAM
	patternBuffer=$(mktemp)
	heisenbergCompensator=""
	if [[ -r $saveLocation ]]; then
		heisenbergCompensator="-z $saveLocation"
	fi
	CMD="$cmd -s $heisenbergCompensator -A '$agent' $url > $patternBuffer"
	$cmd -s $heisenbergCompensator -A "$agent" $url > $patternBuffer


	if [[ -s "$patternBuffer" ]];then
		# Remove comments and print only the domain name
		# Most of the lists downloaded are already in hosts file format but the spacing/formating is not contigious
		# This helps with that and makes it easier to read
		# It also helps with debugging so each stage of the script can be researched more in depth
		awk '($1 !~ /^#/) { if (NF>1) {print $2} else {print $1}}' $patternBuffer | \
			sed -nr -e 's/\.{2,}/./g' -e '/\./p' > $saveLocation
		echo "Done."
	else
		echo "Skipping pattern because transporter logic detected no changes..."
	fi

	# Cleanup
	rm -f $patternBuffer
done

# Find all files with the .domains extension and compile them into one file and remove CRs
echo "** Aggregating list of domains..."
find $origin/ -type f -name "*.$justDomainsExtension" -exec cat {} \; | tr -d '\r' > $origin/$matter

# Append blacklist entries if they exist
if [[ -r $blacklist ]];then
	numberOf=$(cat $blacklist | sed '/^\s*$/d' | wc -l)
	echo "** Blacklisting $numberOf domain(s)..."
	cat $blacklist >> $origin/$matter
fi

###########################
function gravity_advanced() {

	numberOf=$(wc -l < $origin/$andLight)
	echo "** $numberOf domains being pulled in by gravity..."

	# Remove carriage returns and preceding whitespace
	# not really needed anymore?
	cp $origin/$andLight $origin/$supernova

	# Sort and remove duplicates
	sort -u  $origin/$supernova > $origin/$eventHorizon
	numberOf=$(wc -l < $origin/$eventHorizon)
	echo "** $numberOf unique domains trapped in the event horizon."

	# Format domain list as "192.168.x.x domain.com"
	echo "** Formatting domains into a HOSTS file..."
	awk '{print "'"$piholeIP"'" $1}' $origin/$eventHorizon > $origin/$accretionDisc

	# Copy the file over as /etc/pihole/gravity.list so dnsmasq can use it
	sudo cp $origin/$accretionDisc $adList
	kill -HUP $(pidof dnsmasq)
}

# Whitelist (if applicable) then remove duplicates and format for dnsmasq
if [[ -r $whitelist ]];then
	# Remove whitelist entries
	numberOf=$(cat $whitelist | sed '/^\s*$/d' | wc -l)
	plural=; [[ "$numberOf" != "1" ]] && plural=s
	echo "** Whitelisting $numberOf domain${plural}..."

	# Append a "$" to the end, prepend a "^" to the beginning, and
	# replace "." with "\." of each line to turn each entry into a
	# regexp so it can be parsed out with grep -x
	awk -F '[# \t]' 'NF>0&&$1!="" {print "^"$1"$"}' $whitelist | sed 's/\./\\./g' > $latentWhitelist
else
	rm $latentWhitelist
fi

# Prevent our sources from being pulled into the hole
plural=; [[ "${#sources[@]}" != "1" ]] && plural=s
echo "** Whitelisting ${#sources[@]} ad list source${plural}..."
for url in ${sources[@]}
do
	echo "$url" | awk -F '/' '{print "^"$3"$"}' | sed 's/\./\\./g' >> $latentWhitelist
done

# Remove whitelist entries from deduped list
grep -vxf $latentWhitelist $origin/$matter > $origin/$andLight

gravity_advanced
