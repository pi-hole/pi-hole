#!/bin/bash
# For each argument passed to this script
for var in "$@"
do
        echo "Whitelisting $var..."
        # Use sed to search for the domain in /etc/pihole/gravity.list and remove it using an in-place edit
        sed -i "/$var/d" /etc/pihole/gravity.list
        # Also add the domain to the whitelist.txt in /etc/pihole
        echo "$var" >> /etc/pihole/whitelist.txt
done
echo "** $# domain(s) whitelisted."
# Force dnsmasq to reload /etc/pihole/gravity.list
kill -HUP $(pidof dnsmasq)