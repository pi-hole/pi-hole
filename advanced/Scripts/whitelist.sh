#!/usr/bin/env bash
# (c) 2015 by Jacob Salmela
# This file is part of Pi-hole.
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

whiteList=/etc/pihole/whitelist.txt
adList=/etc/pihole/gravity.list
latentWhitelist=/etc/pihole/latentWhitelist.txt
if [[ ! -f $whiteList ]];then
    touch $whiteList
fi

if [[ $# = 0 ]]; then
    echo "Immediately whitelists one or more domains."
    echo "Usage: whitelist.sh domain1 [domain2 ...]"
fi

latentPattern=""
boolA=false
boolB=false
for var in "$@"
do
		bool=false;
    echo "Whitelisting $var..."
    #add to whitelist.txt if it is not already there
    grep -Ex -q "$var" $whiteList || boolB=true
    if $boolB; then
        echo $var >> $whiteList
        #add to latentwhitelist.txt. Double-check it's not already there
        latentPattern=$(echo $var | sed 's/\./\\./g')
        grep -Ex -q "$latentPattern" $whiteList || echo $latentPattern >> $latentWhitelist
        boolA=true;
    else
        echo "$var Already in whitelist.txt"
    fi
done

if $boolA; then
    echo "New domains added to whitelist. Running gravity.sh"
    /usr/local/bin/gravity.sh
else
	echo "No need to update Hosts list, given domains already in whitelist"
fi
