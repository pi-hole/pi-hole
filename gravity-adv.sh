#!/bin/bash
# The Pi-hole now blocks over 90,000 ad domains
# Address to send ads to (the RPi)
piholeIP="127.0.0.1"
# Optionally, uncomment to automatically detect the local IP address.
#piholeIP=$(hostname -I)

# Config file to hold URL rules
eventHorizon="/etc/dnsmasq.d/adList.conf"
piholeDir='/etc/pihole/'     

blacklist=$piholeDir'blacklist.txt'
whitelist=$piholeDir'whitelist.txt'

tmpDir='./tmp/'    
tmpAdPrefix=$tmpDir'matter.pihole'
tmpAdList=$tmpAdPrefix'.txt'
tmpConf=$tmpDir'andLight.pihole.txt'
tmpWhiteList=$tmpDir'yang.pihole.txt'
tmpBlackList=$tmpDir'yin.pihole.txt'

# Create the pihole resource directory if it doesn't exist.  Future files will be stored here
if [[ -d $piholeDir ]];then
	:
else
	echo "Forming pihole directory..."
	sudo mkdir $piholeDir
fi

#if pipe is not empty write it into file $1
writeifne () {
        read pipe || return 1
        { printf "%s\n" "$pipe"; cat; }  > "$1"
}

echo "Getting yoyo ad list..." # Approximately 2452 domains at the time of writing
curl -s -d mimetype=plaintext -d hostformat=unixhosts http://pgl.yoyo.org/adservers/serverlist.php?  -z $tmpAdPrefix."yoyo.txt" -o $tmpAdPrefix."yoyo.txt"
echo "Getting winhelp2002 ad list..." # 12985 domains
curl -s http://winhelp2002.mvps.org/hosts.txt -z $tmpAdPrefix."winhelp2002.txt" | awk '/^[0-9]{1,3}(\.[0-9]{1,3}){3}/ {print $2}' | sed $'s/\r$//' | writeifne $tmpAdPrefix."winhelp2002.txt"
echo "Getting adaway ad list..." # 445 domains
curl -s https://adaway.org/hosts.txt -z $tmpAdPrefix."adaway.txt" | awk '/^[0-9]{1,3}(\.[0-9]{1,3}){3}/ {print $2}' | writeifne $tmpAdPrefix."adaway.txt"
echo "Getting hosts-file ad list..." # 28050 domains
curl -s http://hosts-file.net/.%5Cad_servers.txt -z $tmpAdPrefix."hosts-file.txt" | awk '/^[0-9]{1,3}(\.[0-9]{1,3}){3}/ {print $2}' | sed $'s/\r$//' | writeifne $tmpAdPrefix."hosts-file.txt"
echo "Getting malwaredomainlist ad list..." # 1352 domains
curl -s http://www.malwaredomainlist.com/hostslist/hosts.txt -z $tmpAdPrefix."malwaredomainlist.txt" | awk '/^[0-9]{1,3}(\.[0-9]{1,3}){3}/ {print $2}' | sed $'s/\r$//' | writeifne $tmpAdPrefix."malwaredomainlist.txt"
echo "Getting adblock.gjtech ad list..." # 696 domains
curl -s http://adblock.gjtech.net/?format=unix-hosts -z $tmpAdPrefix."gjtech.txt" | awk '/^[0-9]{1,3}(\.[0-9]{1,3}){3}/ {print $2}' | sed $'s/\r$//' | writeifne $tmpAdPrefix."gjtech.txt"
echo "Getting someone who cares ad list..." # 10600
curl -s http://someonewhocares.org/hosts/hosts -z $tmpAdPrefix."someonewhocares.txt" | awk '/^[0-9]{1,3}(\.[0-9]{1,3}){3}/ {print $2}' | sed $'s/\r$//' | writeifne $tmpAdPrefix."someonewhocares.txt"
echo "Getting Mother of All Ad Blocks list..." # 102168 domains!! Thanks Kacy
curl -A 'Mozilla/5.0 (X11; Linux x86_64; rv:30.0) Gecko/20100101 Firefox/30.0' -e http://forum.xda-developers.com/ http://adblock.mahakala.is/ -z $tmpAdPrefix."mahakala.txt" | awk '/^[0-9]{1,3}(\.[0-9]{1,3}){3}/ {print $2}' | sed $'s/\r$//' | writeifne $tmpAdPrefix."mahakala.txt"

# Merge temporary files. Remove lines with no dots (i.e. localhost, localdomain, etc)
echo -n "" > $tmpAdList
for i in $tmpAdPrefix.*.txt
do
    grep '\.' $i >> $tmpAdList
done

# If newer, add entries from the local blacklist file if it exists in $piholeDir directory
# Remove empty lines and comments
if [[ -f $blacklist ]] && [[ $tmpBlackList -ot $blacklist ]]; then
    echo "Getting the local blacklist from $piholeDir directory"
    awk -F'[# \t]' 'NF>0&&$1!="" {print $1}' $blacklist > $tmpBlackList
else
    if [[ -f $tmpBlackList ]]; then
        echo "No need to update temporary blacklist."
    else
        echo -n "" > $tmpBlackList
    fi
fi
cat $tmpBlackList >> $tmpAdList

# If newer, clean-up entries from the local whitelist file if it exists in $piholeDir directory
# Remove empty lines and comments
if [[ -f $whitelist ]] && [[ $tmpWhiteList -ot $whitelist ]]; then
    echo "Getting the local whitelist from $piholeDir directory"
    awk -F'[# \t]' 'NF>0&&$1!="" {print $1"$"}' $whitelist > $tmpWhiteList 
else
    if [[ -f $tmpWhiteList ]]; then
        echo "No need to update temporary whitelist."
    else
        echo -n "^$" > $tmpWhiteList
    fi
fi

# Sort the aggregated results and remove any duplicates
# Remove entries from the whitelist file if it exists in $piholeDir folder
# Remove all subdomains if domain is already in list
echo "Removing duplicates, whitelisting, and formatting the list of domains..."
awk -F. '{for (i=NF; i>1; --i) printf "%s.",$i;print $1}' $tmpAdList | 
    sort -t'.' -k1,2| uniq |  
    awk -F. 'NR!=1&&substr($0,1,length(p))==p {next} {p=$0".";for (i=NF; i>1; --i) printf "%s.",$i;print $1}'| 
    grep -vwf $tmpWhiteList |
    awk -v "IP=$piholeIP" '{sub(/\r$/,""); print "address=/"$0"/"IP}' > $tmpConf

# Count how many entries from blacklist/whitelist were added so it can be displayed to the user
numberOfSitesWhitelisted=$(cat $tmpWhiteList | wc -l | sed 's/^[ \t]*//')
numberOfSitesBlacklisted=$(cat $tmpBlackList | wc -l | sed 's/^[ \t]*//')
echo "$numberOfSitesWhitelisted domain(s) whitelisted, $numberOfSitesBlacklisted domain(s) blacklisted."

# Count how many domains were added so it can be displayed to the user
numberOfAdsBlocked=$(cat $tmpConf | wc -l | sed 's/^[ \t]*//')
echo "$numberOfAdsBlocked ad domains blocked."

# Turn the file into a dnsmasq config file if necessary
if cmp -s $tmpConf $eventHorizon
then
   echo "dnsmasq config file: $eventHorizon doesn't need to be updated"
   rm $tmpConf
else
    echo "...updating configuration file and restarting dnsmasq"
    sudo mv $tmpConf $eventHorizon
    # Restart DNS
    sudo service dnsmasq restart
fi
