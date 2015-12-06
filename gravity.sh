#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015 by Jacob Salmela GPL 2.0
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Compiles a list of ad-serving domains by downloading them from multiple sources

piholeIPfile=/tmp/piholeIP
if [[ -f $piholeIPfile ]];then
    # If the file exists, it means it was exported from the installation script and we should use that value instead of detecting it in this script
    piholeIP=$(cat $piholeIPfile)
    rm $piholeIPfile
else
    # Otherwise, the IP address can be taken directly from the machine, which will happen when the script is run by the user and not the installation script
	IPv4dev=$(ip route get 8.8.8.8 | awk '{print $5}')
	piholeIPCIDR=$(ip -o -f inet addr show dev $IPv4dev | awk '{print $4}') | sed -n '$p'
	piholeIP=${piholeIPCIDR%/*}
fi

# Ad-list sources--one per line in single quotes
# The mahakala source is commented out due to many users having issues with it blocking legitimate domains.
# Uncomment at your own risk
sources=('https://adaway.org/hosts.txt'
'http://adblock.gjtech.net/?format=unix-hosts'
#'http://adblock.mahakala.is/'
'http://hosts-file.net/ad_servers.txt'
'http://www.malwaredomainlist.com/hostslist/hosts.txt'
'http://pgl.yoyo.org/adservers/serverlist.php?'
'http://someonewhocares.org/hosts/hosts'
'http://winhelp2002.mvps.org/hosts.txt')

# Variables for various stages of downloading and formatting the list
basename=pihole
piholeDir=/etc/$basename
adList=$piholeDir/gravity.list
blacklist=$piholeDir/blacklist.txt
whitelist=$piholeDir/whitelist.txt
latentWhitelist=$piholeDir/latentWhitelist.txt
justDomainsExtension=domains
matter=$basename.0.matter.txt
andLight=$basename.1.andLight.txt
supernova=$basename.2.supernova.txt
eventHorizon=$basename.3.eventHorizon.txt
accretionDisc=$basename.4.accretionDisc.txt
eyeOfTheNeedle=$basename.5.wormhole.txt

# After setting defaults, check if there's local overrides
if [[ -r $piholeDir/pihole.conf ]];then
    echo "** Local calibration requested..."
        . $piholeDir/pihole.conf
fi

###########################
# collapse - begin formation of pihole
function gravity_collapse() {
	echo "** Neutrino emissions detected..."

	# Create the pihole resource directory if it doesn't exist.  Future files will be stored here
	if [[ -d $piholeDir ]];then
        # Temporary hack to allow non-root access to pihole directory
        # Will update later, needed for existing installs, new installs should
        # create this directory as non-root
        sudo chmod 777 $piholeDir
        find "$piholeDir" -type f -exec sudo chmod 666 {} \;
	else
        echo "** Creating pihole directory..."
        mkdir $piholeDir
	fi
}

# patternCheck - check to see if curl downloaded any new files.
function gravity_patternCheck() {
	patternBuffer=$1
	# check if the patternbuffer is a non-zero length file
	if [[ -s "$patternBuffer" ]];then
		# Some of the blocklists are copyright, they need to be downloaded
		# and stored as is. They can be processed for content after they
		# have been saved.
		cp $patternBuffer $saveLocation
		echo "List updated, transport successful..."
	else
		# curl didn't download any host files, probably because of the date check
		echo "No changes detected, transport skipped..."
	fi
}

# transport - curl the specified url with any needed command extentions
function gravity_transport() {
	url=$1
	cmd_ext=$2
	agent=$3

	# tmp file, so we don't have to store the (long!) lists in RAM
	patternBuffer=$(mktemp)
	heisenbergCompensator=""
	if [[ -r $saveLocation ]]; then
		# if domain has been saved, add file for date check to only download newer
		heisenbergCompensator="-z $saveLocation"
	fi

	# Silently curl url
	curl -s $cmd_ext $heisenbergCompensator -A "$agent" $url > $patternBuffer
	# Check for list updates
	gravity_patternCheck $patternBuffer

	# Cleanup
	rm -f $patternBuffer
}

# spinup - main gravity function
function gravity_spinup() {

	# Loop through domain list.  Download each one and remove commented lines (lines beginning with '# 'or '/') and	 		# blank lines
	for ((i = 0; i < "${#sources[@]}"; i++))
	do
        url=${sources[$i]}
        # Get just the domain from the URL
        domain=$(echo "$url" | cut -d'/' -f3)

        # Save the file as list.#.domain
        saveLocation=$piholeDir/list.$i.$domain.$justDomainsExtension
        activeDomains[$i]=$saveLocation

        agent="Mozilla/10.0"

        echo -n "  Getting $domain list: "

        # Use a case statement to download lists that need special cURL commands
        # to complete properly and reset the user agent when required
        case "$domain" in
                "adblock.mahakala.is")
                        agent='Mozilla/5.0 (X11; Linux x86_64; rv:30.0) Gecko/20100101 Firefox/30.0'
                        cmd_ext="-e http://forum.xda-developers.com/"
                        ;;

                "pgl.yoyo.org")
                        cmd_ext="-d mimetype=plaintext -d hostformat=hosts"
                        ;;

                # Default is a simple request
                *) cmd_ext=""
        esac
        gravity_transport $url $cmd_ext $agent
	done
}

# Schwarzchild - aggregate domains to one list and add blacklisted domains
function gravity_Schwarzchild() {

	# Find all active domains and compile them into one file and remove CRs
	echo "** Aggregating list of domains..."
	truncate -s 0 $piholeDir/$matter
	for i in "${activeDomains[@]}"
	do
   		cat $i |tr -d '\r' >> $piholeDir/$matter
	done
}

# Pulsar - White/blacklist application
function gravity_pulsar() {

	# Append blacklist entries if they exist
	if [[ -r $blacklist ]];then
        numberOf=$(cat $blacklist | sed '/^\s*$/d' | wc -l)
        echo "** Blacklisting $numberOf domain(s)..."
        cat $blacklist >> $piholeDir/$matter
	fi

	# Whitelist (if applicable) domains
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
        rm $latentWhitelist >/dev/null
	fi

	# Prevent our sources from being pulled into the hole
	plural=; [[ "${#sources[@]}" != "1" ]] && plural=s
	echo "** Whitelisting ${#sources[@]} ad list source${plural}..."
	for url in ${sources[@]}
	do
        echo "$url" | awk -F '/' '{print "^"$3"$"}' | sed 's/\./\\./g' >> $latentWhitelist
	done

	# Remove whitelist entries from list
	grep -vxf $latentWhitelist $piholeDir/$matter > $piholeDir/$andLight
}

function gravity_unique() {
	# Sort and remove duplicates
	sort -u  $piholeDir/$supernova > $piholeDir/$eventHorizon
	numberOf=$(wc -l < $piholeDir/$eventHorizon)
	echo "** $numberOf unique domains trapped in the event horizon."
}

function gravity_hostFormat() {
	# Format domain list as "192.168.x.x domain.com"
	echo "** Formatting domains into a HOSTS file..."
	cat $piholeDir/$eventHorizon | awk '{sub(/\r$/,""); print "'"$piholeIP"' " $0}' > $piholeDir/$accretionDisc
	# Copy the file over as /etc/pihole/gravity.list so dnsmasq can use it
	cp $piholeDir/$accretionDisc $adList
}

# blackbody - remove any remnant files from script processes
function gravity_blackbody() {
	# Loop through list files
	for file in $piholeDir/*.$justDomainsExtension
	do
		# If list is in active array then leave it (noop) else rm the list
		if [[ " ${activeDomains[@]} " =~ " ${file} " ]]; then
			:
		else
			rm -f $file
		fi
	done
}

function gravity_advanced() {
	# Remove comments and print only the domain name
	# Most of the lists downloaded are already in hosts file format but the spacing/formating is not contigious
	# This helps with that and makes it easier to read
	# It also helps with debugging so each stage of the script can be researched more in depth
	awk '($1 !~ /^#/) { if (NF>1) {print $2} else {print $1}}' $piholeDir/$andLight | \
		sed -nr -e 's/\.{2,}/./g' -e '/\./p' >  $piholeDir/$supernova

	numberOf=$(wc -l < $piholeDir/$supernova)
	echo "** $numberOf domains being pulled in by gravity..."

	gravity_unique

	sudo kill -s -HUP $(pidof dnsmasq)
}

gravity_collapse
gravity_spinup
gravity_Schwarzchild
gravity_pulsar
gravity_advanced
gravity_hostFormat
gravity_blackbody
