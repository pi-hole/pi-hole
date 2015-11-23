#!/usr/bin/env bash
# http://pi-hole.net
# Compiles a list of ad-serving domains by downloading them from multiple sources
piholeIPfile=/tmp/piholeIP
if [[ -f $piholeIPfile ]];then
    # If the file exists, it means it was exported from the installation script and we should use that value instead of detecting it in this script
    piholeIP=$(cat $piholeIPfile)
    rm $piholeIPfile
else
    # Otherwise, the IP address can be taken directly from the machine, which will happen when the script is run by the user and not the installation script
    piholeIP=$(ip -4 addr show | awk '{match($0,/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/); ip = substr($0,RSTART,RLENGTH); print ip}' | sed '/^\s*$/d' | grep -v "127.0.0.1" | (head -n1))
fi

# Ad-list sources--one per line in single quotes
# The mahakala source is commented out due to many users having issues with it blocking legitimate domains.  Uncomment at your own risk
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

# spinup - main gravity function
function gravity_spinup() {

# Loop through domain list.  Download each one and remove commented lines (lines beginning with '# 'or '/') and blank lines
for ((i = 0; i < "${#sources[@]}"; i++))
do
        url=${sources[$i]}
        # Get just the domain from the URL
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
        rm $latentWhitelist
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

function gravity_advanced() {

        numberOf=$(wc -l < $piholeDir/$andLight)
        echo "** $numberOf domains being pulled in by gravity..."

        # Remove carriage returns and preceding whitespace
        # not really needed anymore?
        cp $piholeDir/$andLight $piholeDir/$supernova

        # Sort and remove duplicates
        sort -u  $piholeDir/$supernova > $piholeDir/$eventHorizon
        numberOf=$(wc -l < $piholeDir/$eventHorizon)
        echo "** $numberOf unique domains trapped in the event horizon."

        # Format domain list as "192.168.x.x domain.com"
        echo "** Formatting domains into a HOSTS file..."
        cat $piholeDir/$eventHorizon | awk '{sub(/\r$/,""); print "'"$piholeIP"' " $0}' > $piholeDir/$accretionDisc
        # Copy the file over as /etc/pihole/gravity.list so dnsmasq can use it
        cp $piholeDir/$accretionDisc $adList
        sudo kill -HUP $(pidof dnsmasq)
}

gravity_spinup
gravity_transport
gravity_Schwartzchild
gravity_advanced
