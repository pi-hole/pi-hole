#!/bin/bash
# The Pi-hole now blocks over 90,000 ad domains
# Address to send ads to (the RPi)
piholeIP="192.168.1.110"
# Optionally, uncomment to automatically detect the address.  Thanks Gregg
#piholeIP=$(ifconfig eth0 | awk '/inet addr/{print substr($2,6)}')

# Config file to hold URL rules
piholeDir='/etc/pihole/'     
eventHorizion='/etc/dnsmasq.d/adList.conf'


whitelist=$piholeDir'whitelist.txt'
blacklist=$piholeDir'blacklist.txt'

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


echo -n "" > $tmpWhiteList
if [[ -f $whitelist ]];then
    grep -vE "^\s*(#|$)" $whitelist | sed "s|$|\$|" > $tmpWhiteList
fi

echo -n "" > $tmpBlackList
if [[ -f $blacklist ]];then
    grep -vE "^\s*(#|$)" $blacklist > $tmpBlackList
fi

echo "Getting yoyo ad list..." # Approximately 2452 domains at the time of writing
curl -s -d mimetype=plaintext -d hostformat=unixhosts http://pgl.yoyo.org/adservers/serverlist.php? | sort > $tmpAdList
echo "Getting winhelp2002 ad list..." # 12985 domains
curl -s http://winhelp2002.mvps.org/hosts.txt | grep -v "#" | grep -v "127.0.0.1" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $2}'  >> $tmpAdList
echo "Getting adaway ad list..." # 445 domains
curl -s https://adaway.org/hosts.txt | grep -v "#" | grep -v "::1" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $2}' | grep -v '^\\' | grep -v '\\$'  >> $tmpAdList
echo "Getting hosts-file ad list..." # 28050 domains
curl -s http://hosts-file.net/.%5Cad_servers.txt | grep -v "#" | grep -v "::1" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $2}' | grep -v '^\\' | grep -v '\\$'  >> $tmpAdList
echo "Getting malwaredomainlist ad list..." # 1352 domains
curl -s http://www.malwaredomainlist.com/hostslist/hosts.txt | grep -v "#" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $3}' | grep -v '^\\' | grep -v '\\$'  >> $tmpAdList
echo "Getting adblock.gjtech ad list..." # 696 domains
curl -s http://adblock.gjtech.net/?format=unix-hosts | grep -v "#" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $2}' | grep -v '^\\' | grep -v '\\$'  >> $tmpAdList
echo "Getting someone who cares ad list..." # 10600
curl -s http://someonewhocares.org/hosts/hosts | grep -v "#" | sed '/^$/d' | sed 's/\ /\\ /g' | grep -v '^\\' | grep -v '\\$' | awk '{print $2}' | grep -v '^\\' | grep -v '\\$' >> $tmpAdList
echo "Getting Mother of All Ad Blocks list..." # 102168 domains!! Thanks Kacy
curl -A 'Mozilla/5.0 (X11; Linux x86_64; rv:30.0) Gecko/20100101 Firefox/30.0' -e http://forum.xda-developers.com/ http://adblock.mahakala.is/ | grep -v "#" | awk '{print $2}'  >> $tmpAdList

# Sort the aggregated results and remove any duplicates
# Remove entries from the whitelist file if it exists at the root of the current user's home folder
echo "Removing duplicates, whitelisting, and formatting the list of domains..."
grep -vhE "^\s*(#|$)" $tmpAdList $tmpBlackList | 
    sed $'s/\r$//'| 
    awk -F. '{for (i=NF; i>1; --i) printf "%s.",$i;print $1}'| 
    sort -t'.' -k1,2| uniq |  grep -vwf $tmpWhiteList |
    awk -F. 'NR!=1&&substr($0,0,length(p))==p{next} {p=$0".";for (i=NF; i>1; --i) printf "%s.",$i;print $1}'| 
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
