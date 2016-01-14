#!/usr/bin/env bash
# (c) 2015 by Jacob Salmela
# This file is part of Pi-hole.
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

blackList=/etc/pihole/blacklist.txt
if [[ ! -f $blackList ]];then
    touch $blackList
fi

if [[ $# = 0 ]]; then
    echo "Immediately blacklists one or more domains."
    echo "Usage: blacklist.sh domain1 [domain2 ...]"
fi

boolA=false
boolB=false
for var in "$@"
do
		bool=false;
    echo "Blacklisting $var..."
    #add to whitelist.txt if it is not already there
    grep -Ex -q "$var" $blackList || boolB=true
    if $boolB; then
        echo $var >> $blackList        
        boolA=true;
    else
        echo "$var Already in blacklist.txt"
    fi
done

if $boolA; then
    echo "New domains added to blacklist. Running gravity.sh"
    /usr/local/bin/gravity.sh
else
	echo "No need to update Hosts list, given domains already in blacklist"
fi
