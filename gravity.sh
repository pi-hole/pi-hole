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

###########################
# patternCheck - check to see if curl downloaded any new files, and then process those
# files so they are in host format.
function gravity_patternCheck() {
        patternBuffer=$1
        # check if the patternbuffer is a non-zero length file
        if [[ -s "$patternBuffer" ]];then
                # Remove comments and print only the domain name
                # Most of the lists downloaded are already in hosts file format but the spacing/formating is not contigious
                # This helps with that and makes it easier to read
                # It also helps with debugging so each stage of the script can be researched more in depth
                awk '($1 !~ /^#/) { if (NF>1) {print $2} else {print $1}}' $patternBuffer | \
                        sed -nr -e 's/\.{2,}/./g' -e '/\./p' > $saveLocation
                echo "Done."
        else
                # curl didn't download any host files, probably because of the date check
                echo "Transporter logic detected no changes, pattern skipped..."
        fi
}

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
        # Compress files to singularity and white/blacklist
        gravity_Schwarzchild
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

gravity_advanced
