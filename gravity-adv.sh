#!/bin/bash
# The Pi-hole now blocks over 90,000 ad domains
# Address to send ads to (the RPi)
piholeIP="127.0.0.1"
# Optionally, uncomment to automatically detect the local IP address.
#piholeIP=$(hostname -I)

# Config file to hold URL rules
eventHorizion="/etc/dnsmasq.d/adList.conf"
piholeDir='/etc/pihole/'     

blacklist=$piholeDir'blacklist.txt'
whitelist=$piholeDir'whitelist.txt'

# Create the pihole resource directory if it doesn't exist.  Future files will be stored here
if [[ -d $piholeDir ]];then
	:
else
	echo "Forming pihole directory..."
	sudo mkdir $piholeDir
fi

tmpDir='/tmp/'    
tmpAdList=$tmpDir'matter.pihole.txt'
tmpConf=$tmpDir'andLight.pihole.txt'
tmpWhiteList=$tmpDir'yang.pihole.txt'
tmpBlackList=$tmpDir'yin.pihole.txt'

echo "Getting yoyo ad list..." # Approximately 2452 domains at the time of writing
curl -s -d mimetype=plaintext -d hostformat=unixhosts http://pgl.yoyo.org/adservers/serverlist.php? | sort > $tmpAdList
echo "Getting winhelp2002 ad list..." # 12985 domains
curl -s http://winhelp2002.mvps.org/hosts.txt | grep -v "#" | grep -v "127.0.0.1" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $2}' >> $tmpAdList
echo "Getting adaway ad list..." # 445 domains
curl -s https://adaway.org/hosts.txt | grep -v "#" | grep -v "::1" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $2}' | grep -v '^\\' | grep -v '\\$' >> $tmpAdList
echo "Getting hosts-file ad list..." # 28050 domains
curl -s http://hosts-file.net/.%5Cad_servers.txt | grep -v "#" | grep -v "::1" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $2}' | grep -v '^\\' | grep -v '\\$' >> $tmpAdList
echo "Getting malwaredomainlist ad list..." # 1352 domains
curl -s http://www.malwaredomainlist.com/hostslist/hosts.txt | grep -v "#" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $3}' | grep -v '^\\' | grep -v '\\$'  >> $tmpAdList
echo "Getting adblock.gjtech ad list..." # 696 domains
curl -s http://adblock.gjtech.net/?format=unix-hosts | grep -v "#" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $2}' | grep -v '^\\' | grep -v '\\$' >> $tmpAdList
echo "Getting someone who cares ad list..." # 10600
curl -s http://someonewhocares.org/hosts/hosts | grep -v "#" | sed '/^$/d' | sed 's/\ /\\ /g' | grep -v '^\\' | grep -v '\\$' | awk '{print $2}' | grep -v '^\\' | grep -v '\\$' >> $tmpAdList
echo "Getting Mother of All Ad Blocks list..." # 102168 domains!! Thanks Kacy
curl -A 'Mozilla/5.0 (X11; Linux x86_64; rv:30.0) Gecko/20100101 Firefox/30.0' -e http://forum.xda-developers.com/ http://adblock.mahakala.is/ | grep -v "#" | awk '{print $2}' >> $tmpAdList

# Add entries from the local blacklist file if it exists in $piholeDir directory
echo -n "" > $tmpBlackList
if [[ -f $blacklist ]];then
    echo "Getting the local blacklist from $piholeDir directory"
    awk -F'[# \t]' 'NF>0&&$1!="" {print $1}' $blacklist > $tmpBlackList
    cat $tmpBlackList >> $tmpAdList
fi

# Clean-up entries from the local whitelist file if it exists in $piholeDir directory
echo -n "^$" > $tmpWhiteList
if [[ -f $whitelist ]];then
    echo "Getting the local whitelist from $piholeDir directory"
    awk -F'[# \t]' 'NF>0&&$1!="" {print $1"$"}' $whitelist > $tmpWhiteList
fi

# Sort the aggregated results and remove any duplicates
# Remove entries from the whitelist file if it exists in $piholeDir folder
echo "Removing duplicates, whitelisting, and formatting the list of domains..."
grep -vhE "^\s*(#|$)" $tmpAdList| 
    sed $'s/\r$//'| 
    awk -F. '{for (i=NF; i>1; --i) printf "%s.",$i;print $1}'| 
    sort -t'.' -k1,2| uniq |  
    awk -F. 'NR!=1&&substr($0,1,length(p))==p {next} {p=$0".";for (i=NF; i>1; --i) printf "%s.",$i;print $1}'| 
    grep -vwf $tmpWhiteList |
    awk -v "IP=$piholeIP" '{sub(/\r$/,""); print "address=/"$0"/"IP}' > $tmpConf
numberOfSitesWhitelisted=$(cat $tmpWhiteList | wc -l | sed 's/^[ \t]*//')
numberOfSitesBlacklisted=$(cat $tmpBlackList | wc -l | sed 's/^[ \t]*//')
echo "$numberOfSitesWhitelisted domain(s) whitelisted, $numberOfSitesBlacklisted domain(s) blacklisted."

# Count how many domains/whitelists were added so it can be displayed to the user
numberOfAdsBlocked=$(cat $tmpConf | wc -l | sed 's/^[ \t]*//')
echo "$numberOfAdsBlocked ad domains blocked."

# Turn the file into a dnsmasq config file
sudo mv $tmpConf $eventHorizion

# Restart DNS
sudo service dnsmasq restart
